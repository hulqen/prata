#!/bin/sh
# Laddar om Hammerspoon, tvingar fram skräpsamling medan modellen laddar, och kontrollerar att tjänsten blir redo.
HS="perl -e alarm(5);exec(@ARGV) $(command -v hs)"  # hård tidsgräns: hs -t håller den inte under omstart
killall Hammerspoon; sleep 1; open -g -a Hammerspoon
sleep 2  # skräpsamlingen måste ske medan modellen laddar (ca 2 s); hs-anrop som hinner före IPC-porten får tidsgräns
for i in 1 2 3 4 5 6 7 8; do $HS -t 3 -c 'collectgarbage("collect")' >/dev/null 2>&1; sleep 0.3; done
sleep 3
RES=$($HS -t 3 -c 'local s=prata.status(); print("redo="..tostring(s.redo).." tjanst="..tostring(s.tjanst).." lage="..s.lage.." tangent="..s.tangent)')
echo "$RES"
echo "$RES" | grep -q "redo=true"
