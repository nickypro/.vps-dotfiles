#!/bin/bash
# Run INSIDE the container (`make net-test` copies it in and passes the host's
# public IP): prints what the container can reach. With "cell" as the second
# argument it runs as an isolated agent and checks its tighter rules too.
pub=${1:-}
mode=${2:-dev}
t() { if timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then r=open; else r=blocked; fi
      [ "$r" = "$4" ] && ok=" " || ok="!"
      printf ' %s %-8s %-22s %s (want %s)\n' "$ok" "$r" "$1:$2" "$3" "$4"; }
# Default gateway (= the host's address on the bridge), from /proc/net/route.
h=$(awk '$2 == "00000000" {print $3; exit}' /proc/net/route)
gw=$(printf '%d.%d.%d.%d' 0x${h:6:2} 0x${h:4:2} 0x${h:2:2} 0x${h:0:2})
t 169.254.169.254 80 "cloud metadata" blocked
t "$gw" 22 "host sshd, bridge" blocked
[ -n "$pub" ] && t "$pub" 22 "host sshd, public IP" blocked
t 1.1.1.1 443 "internet" open
getent hosts github.com >/dev/null && r=open || r=BROKEN
printf ' %s %-8s %-22s %s (want %s)\n' "$([ $r = open ] && echo ' ' || echo '!')" "$r" "DNS" "github.com" open
if [ "$mode" = cell ]; then
  me=$(hostname -i 2>/dev/null | awk '{print $1}')
  t 127.0.0.1 2222 "this box's sshd" blocked
  t "$me" 3773 "T3's API, via the box's IP" blocked
  t 127.0.0.1 3773 "T3's API" blocked
  t "$gw" 443 "host nginx, bridge" blocked
  python3 -m http.server 20123 --bind 127.0.0.1 >/dev/null 2>&1 & s=$!
  sleep 1
  t 127.0.0.1 20123 "its own server, 20000-29999" open
  kill $s 2>/dev/null
  n=$(ps -e --no-headers | wc -l)
  [ "$n" -lt 20 ] && r=hidden || r=VISIBLE
  printf ' %s %-8s %-22s %s\n' "$([ $r = hidden ] && echo ' ' || echo '!')" "$r" "other users' processes" "($n visible, want only its own)"
fi
