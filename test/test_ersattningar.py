import sys, os, tempfile; sys.path.insert(0, sys.argv[1])
import dikt_server as ds
f = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
f.write("# kommentar\nWaldemars Kvarn = Valdemars kvarn, Valdemar kvarn, Valdemas kvarn\nWaldemar = Valdemar\n\nfelrad utan likhetstecken\n"); f.close()
regler = ds.las_ersattningar(f.name)
fall = [
    ("Nu testar jag Valdemar kvarn flera gånger.", "Nu testar jag Waldemars Kvarn flera gånger."),
    ("valdemas Kvarn ligger i Göteborg", "Waldemars Kvarn ligger i Göteborg"),
    ("Valdemars kvarn och Valdemar mjöl", "Waldemars Kvarn och Waldemar mjöl"),
    ("Valdemarsgatan är gott", "Valdemarsgatan är gott"),          # bara hela ord
    ("Inget att rätta här.", "Inget att rätta här."),
]
fel = 0
for in_, vantat in fall:
    ut = ds.tillampa_ersattningar(in_, regler)
    ok = ut == vantat; fel += not ok
    print("OK " if ok else "FEL", repr(in_), "->", repr(ut))
print("saknad fil ->", ds.las_ersattningar("/finns/inte.txt"))
sys.exit(fel)
