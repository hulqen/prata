# Saknade användarfiler skapas från exempelfilerna, men befintliga filer rörs aldrig.
import sys, os, tempfile; sys.path.insert(0, sys.argv[1])
import dikt_server as ds
d = tempfile.mkdtemp()
open(os.path.join(d, "ordlista.exempel.txt"), "w").write("# exempel\nTerm\n")
open(os.path.join(d, "ordlista.txt"), "w").write("Min egen\n")
open(os.path.join(d, "ersattningar.exempel.txt"), "w").write("# exempel\nA = a\n")
ds.skapa_fran_exempel(d)
fel = 0
for namn, vantat in [("ordlista.txt", "Min egen\n"), ("ersattningar.txt", "# exempel\nA = a\n")]:
    ok = open(os.path.join(d, namn)).read() == vantat
    fel += not ok
    print("OK " if ok else "FEL", namn)
sys.exit(fel)
