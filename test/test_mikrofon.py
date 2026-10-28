# Testar mikrofonhanteringen utan modell och utan riktig mikrofon.
# 1. Öppningen misslyckas med inaktuell enhetslista: PortAudio ska läsas in på nytt och öppningen göras om.
# 2. Stängningen låser sig: ljudet ska ändå lämnas tillbaka och tjänsten markeras för omstart i stället för att dö direkt.
import sys, threading; sys.path.insert(0, sys.argv[1])
import numpy as np, dikt_server as ds

d = object.__new__(ds.Diktering)
d.lock = threading.Lock(); d.stream = None; d.chunks = []; d.starta_om = False

anrop = []
class Strom:
    def __init__(self, callback, **kw):
        if not anrop.count("init"):
            raise ds.sd.PortAudioError("Error opening InputStream: Internal PortAudio error", -9986)
        self.cb = callback
    def start(self): self.cb(np.ones((160, 1), np.float32), 160, None, None)
    def stop(self): pass
    def close(self): pass
orig = ds.sd.InputStream, ds.sd._terminate, ds.sd._initialize
ds.sd.InputStream = Strom
ds.sd._terminate = lambda: anrop.append("term")
ds.sd._initialize = lambda: anrop.append("init")
d.start()
assert anrop == ["term", "init"], anrop
assert d.stream is not None
ds.sd.InputStream, ds.sd._terminate, ds.sd._initialize = orig  # annars hänger sounddevice vid avslut
print("öppning efter ominläsning: OK")

hang = threading.Event()
class Fast:
    def stop(self): hang.wait()
    def close(self): pass
ds.STOPPTID_MAX = 0.2
d.stream = Fast(); d.chunks = [np.ones(100, np.float32)]
audio = d._stoppa()
assert audio is not None and len(audio) == 100, audio
assert d.starta_om
hang.set()
print("låst stängning ger ljudet: OK")
