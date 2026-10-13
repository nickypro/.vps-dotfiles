#!/bin/bash
# Run INSIDE the container (`make net-test` copies it in and passes the host's
# public IP). Prints what the container can reach.
pub=${1:-}
t() { if timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then r=open; else r=blocked; fi
      printf '  %-8s %-22s %s (want %s)\n' "$r" "$1:$2" "$3" "$4"; }
# Default gateway (= the host's address on the bridge), from /proc/net/route.
h=$(awk '$2 == "00000000" {print $3; exit}' /proc/net/route)
gw=$(printf '%d.%d.%d.%d' 0x${h:6:2} 0x${h:4:2} 0x${h:2:2} 0x${h:0:2})
t 169.254.169.254 80 "cloud metadata" blocked
t "$gw" 22 "host sshd, bridge" blocked
[ -n "$pub" ] && t "$pub" 22 "host sshd, public IP" blocked
t 1.1.1.1 443 "internet" open
getent hosts github.com >/dev/null && r=open || r=BROKEN
printf '  %-8s %-22s %s (want %s)\n' "$r" "DNS" "github.com" open
