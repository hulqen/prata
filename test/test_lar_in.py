import sys, tempfile; sys.path.insert(0, sys.argv[1])
import dikt_server as ds

def fil(innehall):
    f = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8"); f.write(innehall); f.close(); return f.name

def las(p): return open(p, encoding="utf-8").read()

fel = 0
def kolla(namn, villkor, info=""):
    global fel
    fel += not villkor
    print("OK " if villkor else "FEL", namn, info)

BAS = "# kommentar\nWaldemars Kvarn = Valdemars kvarn, Valdemas kvarn\n"

p = fil(BAS); ds.lagg_till_ersattning("Waldemars Kvarn", "Valdemar kvan", p)
kolla("ny felstavning läggs på befintlig rad", las(p) == "# kommentar\nWaldemars Kvarn = Valdemars kvarn, Valdemas kvarn, Valdemar kvan\n", repr(las(p)))

p = fil(BAS); ds.lagg_till_ersattning("Göteborg", "Goteborg", p)
kolla("ny rad skapas för ny stavning", las(p) == BAS + "Göteborg = Goteborg\n", repr(las(p)))

p = fil(BAS.rstrip("\n")); ds.lagg_till_ersattning("Göteborg", "Goteborg", p)
kolla("ny rad hamnar på egen rad även utan avslutande radbrytning", las(p).endswith("Valdemas kvarn\nGöteborg = Goteborg\n"), repr(las(p)))

p = fil(BAS); m = ds.lagg_till_ersattning("Waldemars Kvarn", "valdemas KVARN", p)
kolla("redan känd felstavning (annat skiftläge) ändrar inget", las(p) == BAS, m)

p = fil("Waldemars Kvarn = Valdemars kvarn\nBarbro = Valdemars kvarn\n"); ds.lagg_till_ersattning("Barbro", "Valdemars kvarn", p)
kolla("felstavning flyttas från annan rad (senaste vinner)", las(p) == "Waldemars Kvarn = \nBarbro = Valdemars kvarn\n" or las(p) == "Barbro = Valdemars kvarn\n", repr(las(p)))

p = fil(""); ds.lagg_till_ersattning("Waldemar", "Valdemar", p)
regler = ds.las_ersattningar(p)
kolla("resultatet går att läsa och tillämpa", ds.tillampa_ersattningar("Valdemar mjöl", regler) == "Waldemar mjöl")

p = ds.ERSATTNINGAR + ".finns-inte"
import os
try:
    ds.lagg_till_ersattning("Waldemar", "Valdemar", p); kolla("saknad fil skapas", las(p) == "Waldemar = Valdemar\n")
finally:
    if os.path.exists(p): os.remove(p)

for ratt, felst in [("", "x"), ("x", ""), ("a=b", "x"), ("x", "a,b"), ("x", "a=b"), ("x\ny", "z"), ("Samma", "Samma")]:
    p = fil(BAS)
    try:
        ds.lagg_till_ersattning(ratt, felst, p); kolla(f"ogiltigt {ratt!r}/{felst!r} avvisas", False)
    except ValueError:
        kolla(f"ogiltigt {ratt!r}/{felst!r} avvisas", las(p) == BAS)
sys.exit(fel)
