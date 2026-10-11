# Prata

Diktering på svenska i valfri app på Mac. Håll in höger Option, prata och släpp, så klistras texten in där markören står. Talet tolkas av den svenska taligenkänningsmodellen [Pianissimo från KlangAI](https://huggingface.co/KlangAI/pianissimo-sv-mlx-8bit), som körs helt lokalt på datorn. Inget ljud och ingen text skickas ut på nätet.

Modellen ligger laddad i minnet (cirka 1 GB), så en diktering på tio sekunder tolkas på ungefär 0,2–0,4 sekunder på en M1 Max.

## Krav

- Mac med Apple silicon (M1 eller senare)
- macOS med [Homebrew](https://brew.sh)
- Cirka 1,3 GB ledigt diskutrymme: modellen är 0,7 GB och Python-miljön 0,5 GB

Installationsskriptet installerar det som saknas av [uv](https://github.com/astral-sh/uv) och [Hammerspoon](https://www.hammerspoon.org) via Homebrew.

## Installation

```bash
git clone https://github.com/hulqen/prata.git ~/prata
cd ~/prata
./installera.sh
```

Skriptet bygger en egen Python-miljö (3.12) i `.venv`, hämtar modellen och lägger till några rader i `~/.hammerspoon/init.lua`, om de inte redan finns. Systemets Python berörs inte. Mappen kan ligga var som helst.

Efter installationen:

1. Starta Hammerspoon.
2. Ge Hammerspoon behörighet under **Systeminställningar > Integritet och säkerhet > Hjälpmedel**. Den behövs för att Hammerspoon ska se dikteringstangenten i alla appar och kunna klistra in texten.
3. Håll in höger Option och prata i en textruta. Godkänn frågan om **Mikrofon** första gången. Mikrofonbehörigheten hamnar på Hammerspoon, eftersom det är Hammerspoon som startar tjänsten.
4. Valfritt: slå på *Launch Hammerspoon at login* i Hammerspoons inställningar, så startar dikteringen vid inloggning.

## Användning

Allt styrs från mikrofonsymbolen i menyraden, och där finns också en utförlig hjälp under **Hjälp …**. Det viktigaste:

- **Läge:** håll in och prata, eller tryck för att starta och tryck igen för att stoppa (Esc avbryter).
- **Tangent:** höger Option, Command, Shift eller Control, eller fn/🌐.
- **Ordlista** (`ordlista.txt`): namn och facktermer som modellen hellre ska välja när den tvekar.
- **Ersättningar** (`ersattningar.txt`): rättar texten efter tolkningen, till exempel när två stavningar låter likadant (Waldemar/Valdemar). Formatet är `Rätt = fel, fel`.
- **⌃⌥R:** markera en felstavning i valfri app, tryck ⌃⌥R och skriv rätt stavning. Texten byts ut och rättningen sparas bland ersättningarna.

`ordlista.txt` och `ersattningar.txt` skapas från exempelfilerna vid första start. De versionshanteras inte, så dina egna namn och termer stannar på datorn.

## Så fungerar det

| Del | Fil | Uppgift |
|---|---|---|
| Hammerspoon | `hammerspoon/dikt.lua` | Tangenten, menyraden, inklistringen och ⌃⌥R. Startar tjänsten och startar om den om den kraschar. |
| Tjänsten | `dikt_server.py` | Håller modellen laddad, spelar in, transkriberar och tillämpar ersättningarna. Lyssnar bara på `127.0.0.1:47821`. |
| Hjälpen | `hjalp.html` | Visas från menyn. |

Tekniska detaljer som kan vara bra att känna till om du bygger vidare:

- MLX kräver att modellen körs i samma tråd som den laddades i. Allt modellarbete går därför via en enda arbetstråd.
- Om mikrofonen stängs innan macOS har levererat första ljudet kan PortAudio låsa sig. Tjänsten väntar därför på första ljudblocket innan den stänger, och om stängningen ändå hänger sig avslutar den sig själv, så att Hammerspoon startar en ny.
- Timers i Hammerspoon som inte sparas i en variabel kan städas bort innan de körs. Alla fördröjda anrop går därför via `senare()`.
- Modellens ordlista (boost) kan inte vända stavningar som låter exakt likadant. Höga värden på `boost_alpha` får modellen att upprepa ordlisteorden. Därför finns ersättningslistan.
- Vid varje start kontrollerar tjänsten om det finns en ny version av modellen. Utan nätanslutning används den version som redan finns på datorn.

## Tester

```bash
test/kor_alla.sh
```

Testet `test_redo` startar om Hammerspoon. Hoppa över det med `UTAN_HAMMERSPOON=1 test/kor_alla.sh`. Testljudet skapas med macOS-rösten Alva.

## Avinstallation

Ta bort raderna om Prata i `~/.hammerspoon/init.lua` och radera projektmappen. Modellen ligger i `~/.cache/huggingface/hub/models--KlangAI--pianissimo-sv-mlx-8bit` och kan raderas separat.

## Upphov och licenser

Utvecklad av Johan Wallén tillsammans med Claude (Opus 5.5) från Anthropic, oktober 2026. Koden är licensierad under [MIT](LICENSE).

Modellen ingår inte i det här arkivet utan hämtas från Hugging Face vid installationen. **Pianissimo** är utvecklad av KlangAI och är en svensk finjustering av NVIDIA Parakeet TDT 0.6B v3. Den är licensierad under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Byggd med [parakeet-mlx](https://github.com/senstella/parakeet-mlx), [MLX](https://github.com/ml-explore/mlx), [sounddevice](https://python-sounddevice.readthedocs.io) och [Hammerspoon](https://www.hammerspoon.org).
