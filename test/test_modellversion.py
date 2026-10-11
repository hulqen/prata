# Modellen ska hämtas i exakt den låsta versionen, och fungera utan nätanslutning när den redan finns.
import os, sys, subprocess
mapp = sys.argv[1]
kod = "import dikt_server as d; p = d.hamta_modell(); print(d.MODELL_VERSION); print(p)"
fel = 0
for namn, miljo in [("med nät", {}), ("utan nät", {"HF_ENDPOINT": "http://127.0.0.1:9"})]:
    r = subprocess.run([sys.executable, "-c", kod], cwd=mapp, capture_output=True, text=True, env={**os.environ, **miljo})
    rader = r.stdout.split()
    ok = r.returncode == 0 and len(rader) == 2 and len(rader[0]) == 40 and rader[1].rstrip("/").endswith(rader[0])
    fel += not ok
    print("OK " if ok else "FEL", namn, rader or r.stderr.strip().splitlines()[-1:])
sys.exit(fel)
