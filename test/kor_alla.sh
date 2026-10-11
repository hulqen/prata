#!/bin/sh
# Kör alla tester. Kör från projektmappen: test/kor_alla.sh
# test_redo.sh startar om Hammerspoon och kräver att det är installerat; hoppa över med UTAN_HAMMERSPOON=1.
MAPP="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MAPP"
PY=.venv/bin/python
[ -f test/test.aiff ] || say -v Alva -o test/test.aiff "Hej, det här är ett test av svensk taligenkänning. Modellen ska transkribera den här meningen ordagrant."
fel=0
for t in test_ersattningar test_lar_in test_exempel test_tradar test_server; do
  if $PY test/$t.py "$MAPP" test/test.aiff >/dev/null 2>&1; then echo "OK   $t"; else echo "FEL  $t"; fel=1; fi
done
if test/test_foralder.sh >/dev/null 2>&1; then echo "OK   test_foralder"; else echo "FEL  test_foralder"; fel=1; fi
if [ -z "$UTAN_HAMMERSPOON" ]; then
  if test/test_redo.sh >/dev/null 2>&1; then echo "OK   test_redo"; else echo "FEL  test_redo"; fel=1; fi
fi
exit $fel
