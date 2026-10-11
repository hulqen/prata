#!/bin/sh
# Tjänsten ska avsluta sig när processen som startade den försvinner (t.ex. när Hammerspoon dödas).
# Startar en extra tjänst på en egen port, så att den vanliga dikteringen inte påverkas.
MAPP="$(cd "$(dirname "$0")/.." && pwd)"
PORT=47899
DIKT_PORT=$PORT sh -c "\"$MAPP/.venv/bin/python\" \"$MAPP/dikt_server.py\"; :" >/dev/null 2>&1 &
FORALDER=$!
for i in $(seq 1 60); do curl -s -m 1 127.0.0.1:$PORT/ping >/dev/null && break; sleep 0.5; done
TJANST=$(pgrep -P $FORALDER -f dikt_server.py)
[ -n "$TJANST" ] || { echo "FEL: tjänsten startade inte"; kill $FORALDER; exit 1; }
kill -9 $FORALDER
for i in $(seq 1 10); do kill -0 $TJANST 2>/dev/null || { echo "OK: tjänsten avslutades efter föräldern"; exit 0; }; sleep 0.5; done
echo "FEL: tjänsten (pid $TJANST) lever kvar 5 s efter att föräldern dödats"
kill $TJANST
exit 1
