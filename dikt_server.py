"""Prata – lokal dikteringstjänst: håller modellen Pianissimo laddad, spelar in på begäran och transkriberar.

Lyssnar bara på 127.0.0.1. Endpoints (POST):
  /start  – börja spela in
  /stop   – sluta spela in, transkribera, svara {"text": ..., "sekunder": ...}
  /avbryt – sluta spela in och kasta ljudet
  /lar_in – {"ratt": ..., "fel": ...}: lägg till en ersättning i ersattningar.txt
  /ping   – (GET) kontrollera att tjänsten lever
"""
import json
import os
import re
import shutil
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import sounddevice as sd

HERE = os.path.dirname(os.path.abspath(__file__))
ORDLISTA = os.path.join(HERE, "ordlista.txt")
ERSATTNINGAR = os.path.join(HERE, "ersattningar.txt")
PORT = int(os.environ.get("DIKT_PORT", "47821"))
SR = 16000
MIN_SEKUNDER = 0.3
STARTTID_MAX = 1.0   # längsta väntan på första ljudet efter att mikrofonen öppnats
STOPPTID_MAX = 3.0   # längsta tillåtna tid för att stänga mikrofonen


def logga(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)


def skapa_fran_exempel(mapp=HERE):
    """Skapar ordlista.txt och ersattningar.txt från exempelfilerna om de saknas.
    De egna filerna versionshanteras inte, så en nyklonad mapp har bara exemplen."""
    for namn in ("ordlista", "ersattningar"):
        egen = os.path.join(mapp, f"{namn}.txt")
        exempel = os.path.join(mapp, f"{namn}.exempel.txt")
        if not os.path.exists(egen) and os.path.exists(exempel):
            shutil.copyfile(exempel, egen)


def las_ordlista():
    """En term per rad. Tomma rader och rader som börjar med # hoppas över."""
    try:
        with open(ORDLISTA, encoding="utf-8") as f:
            return [r.strip() for r in f if r.strip() and not r.lstrip().startswith("#")]
    except FileNotFoundError:
        return []


def las_ersattningar(sokvag=ERSATTNINGAR):
    """Rader på formen 'Rätt = fel1, fel2'. Returnerar [(fel, rätt)], längsta felstavning först."""
    regler = []
    try:
        with open(sokvag, encoding="utf-8") as f:
            for rad in f:
                rad = rad.strip()
                if not rad or rad.startswith("#") or "=" not in rad:
                    continue
                ratt, fela = rad.split("=", 1)
                regler += [(fel.strip(), ratt.strip()) for fel in fela.split(",") if fel.strip()]
    except FileNotFoundError:
        pass
    return sorted(regler, key=lambda r: -len(r[0]))


def lagg_till_ersattning(ratt, fel, sokvag=ERSATTNINGAR):
    """Lägger till felstavningen på raden för den rätta stavningen, eller skapar en ny rad.
    En felstavning som redan finns under en annan rätt stavning flyttas hit. Returnerar ett
    meddelande till användaren. Kastar ValueError för värden som skulle förstöra filens format."""
    ratt, fel = ratt.strip(), fel.strip()
    if not ratt or not fel:
        raise ValueError("Både rätt stavning och felstavning behövs")
    if "=" in ratt or "\n" in ratt or any(t in fel for t in "=,\n"):
        raise ValueError("Tecknen = och , kan inte ingå i en ersättning")
    if ratt == fel:
        raise ValueError("Rätt stavning och felstavning är likadana")
    try:
        with open(sokvag, encoding="utf-8") as f:
            rader = f.read().splitlines()
    except FileNotFoundError:
        rader = []

    ut, hittad, redan = [], False, False
    for rad in rader:
        if not rad.strip() or rad.lstrip().startswith("#") or "=" not in rad:
            ut.append(rad)
            continue
        vanster, hoger = rad.split("=", 1)
        felstavningar = [x.strip() for x in hoger.split(",") if x.strip()]
        if vanster.strip() == ratt:
            hittad = True
            if any(x.lower() == fel.lower() for x in felstavningar):
                redan = True
            else:
                felstavningar.append(fel)
        else:
            felstavningar = [x for x in felstavningar if x.lower() != fel.lower()]
            if not felstavningar:
                continue  # raden blev tom när felstavningen flyttades
        ut.append(f"{vanster.strip()} = {', '.join(felstavningar)}")
    if not hittad:
        ut.append(f"{ratt} = {fel}")
    if redan and ut == rader:
        return f"”{fel}” rättas redan till ”{ratt}”"
    with open(sokvag, "w", encoding="utf-8") as f:
        f.write("\n".join(ut) + "\n")
    return f"Sparat: ”{fel}” blir ”{ratt}”"


def tillampa_ersattningar(text, regler):
    """Byter hela ord och fraser, oavsett skiftläge, i ett enda svep."""
    if not regler:
        return text
    tabell = {fel.lower(): ratt for fel, ratt in regler}
    monster = re.compile(r"\b(" + "|".join(re.escape(fel) for fel, _ in regler) + r")\b", re.IGNORECASE)
    return monster.sub(lambda m: tabell[m.group(0).lower()], text)


class Diktering:
    def __init__(self):
        # MLX kräver att modellen laddas och körs i samma tråd. Allt modellarbete går därför
        # via en enda arbetstråd, medan webbservern hanterar anropen i egna trådar.
        self.arbetare = ThreadPoolExecutor(max_workers=1)
        self.arbetare.submit(self._ladda).result()
        self.lock = threading.Lock()
        self.stream = None
        self.chunks = []

    def _ladda(self):
        from huggingface_hub import snapshot_download
        t = time.perf_counter()
        path = snapshot_download("KlangAI/pianissimo-sv-mlx-8bit")
        sys.path.append(path)
        import pianissimo_mlx
        self.pm = pianissimo_mlx
        self.model = pianissimo_mlx.load(path)
        self._transkribera(np.zeros(SR, dtype=np.float32), None)  # uppvärmning
        logga(f"Modellen laddad och uppvärmd på {time.perf_counter() - t:.1f} s")

    def _transkribera(self, audio, boost):
        import mlx.core as mx
        text = self.pm.transcribe(self.model, audio, boost=boost or None).text.strip()
        mx.clear_cache()  # lämna tillbaka arbetsminnet; bara vikterna ligger kvar mellan dikteringarna
        return text

    def _callback(self, indata, frames, tid, status):
        self.chunks.append(indata[:, 0].copy())
        self.forsta_ljud.set()

    def start(self):
        with self.lock:
            if self.stream is not None:
                return
            self.chunks = []
            self.forsta_ljud = threading.Event()
            self.stream = sd.InputStream(samplerate=SR, channels=1, dtype="float32", callback=self._callback)
            self.stream.start()
            # Att stänga strömmen innan macOS levererat första ljudet kan låsa PortAudio (dödläge i
            # AudioOutputUnitStop). Vänta därför tills ljudet faktiskt flödar.
            if not self.forsta_ljud.wait(STARTTID_MAX):
                logga("Varning: inget ljud från mikrofonen efter", STARTTID_MAX, "s")

    def _stoppa(self):
        with self.lock:
            if self.stream is None:
                return None
            stream, self.stream = self.stream, None
            # Skyddsnät: om stängningen ändå låser sig avslutas tjänsten. Då släpper macOS mikrofonen
            # och Hammerspoon startar en ny tjänst.
            t = threading.Thread(target=lambda: (stream.stop(), stream.close()), daemon=True)
            t.start()
            t.join(STOPPTID_MAX)
            if t.is_alive():
                logga(f"Ljudet låste sig vid stängning i mer än {STOPPTID_MAX} s, tjänsten startar om")
                os._exit(3)
            return np.concatenate(self.chunks) if self.chunks else np.zeros(0, dtype=np.float32)

    def avbryt(self):
        self._stoppa()

    def stop(self):
        audio = self._stoppa()
        if audio is None or len(audio) < MIN_SEKUNDER * SR:
            return "", 0.0
        boost = las_ordlista()
        t = time.perf_counter()
        text = self.arbetare.submit(self._transkribera, audio, boost).result()
        ratt = tillampa_ersattningar(text, las_ersattningar())
        logga(f"{len(audio) / SR:.1f} s ljud -> {time.perf_counter() - t:.2f} s: {ratt}"
              + (f"   [före ersättning: {text}]" if ratt != text else ""))
        text = ratt
        return text, len(audio) / SR


def main():
    skapa_fran_exempel()
    d = Diktering()

    class Handler(BaseHTTPRequestHandler):
        def _svara(self, data, status=200):
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self._svara({"ok": True} if self.path == "/ping" else {"fel": "okänd"}, 200 if self.path == "/ping" else 404)

        def do_POST(self):
            try:
                if self.path == "/start":
                    d.start()
                    self._svara({"ok": True})
                elif self.path == "/stop":
                    text, sek = d.stop()
                    self._svara({"text": text, "sekunder": sek})
                elif self.path == "/lar_in":
                    data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
                    try:
                        self._svara({"meddelande": lagg_till_ersattning(data.get("ratt", ""), data.get("fel", ""))})
                    except ValueError as e:
                        self._svara({"fel": str(e)}, 400)
                elif self.path == "/avbryt":
                    d.avbryt()
                    self._svara({"ok": True})
                else:
                    self._svara({"fel": "okänd"}, 404)
            except Exception as e:  # svara alltid, så att Hammerspoon inte hänger
                logga("Fel:", repr(e))
                self._svara({"fel": str(e)}, 500)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    logga(f"Lyssnar på 127.0.0.1:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
