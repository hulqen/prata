# Återskapar felet: stop() anropas från en annan tråd än den som laddade modellen, som i webbservern.
import sys, threading; sys.path.insert(0, sys.argv[1])
import dikt_server as ds
d = ds.Diktering()
import pianissimo_mlx
audio = pianissimo_mlx.read_audio(sys.argv[2])
F = type("F", (), {"stop": lambda s: None, "close": lambda s: None})
res = {}
def kor(i):
    d.stream = F(); d.chunks = [audio]
    try: res[i] = d.stop()[0][:40]
    except Exception as e: res[i] = "FEL " + repr(e)
for i in range(3):
    t = threading.Thread(target=kor, args=(i,)); t.start(); t.join()
print(res)
sys.exit(0 if all(not v.startswith("FEL") for v in res.values()) else 1)
