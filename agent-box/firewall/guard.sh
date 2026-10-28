#!/bin/sh
# Keep the agent-box container off the host and off internal networks.
#
# The container still reaches the whole internet and the host's 80/443 (so
# agents can fetch your own nginx sites). Dropped: every other host port
# (sshd, databases, other apps), the cloud metadata service (169.254.169.254,
# which on some clouds hands out credentials) and private ranges, including
# Tailscale's 100.64/10 -- so in tailscale mode agents cannot reach your
# other devices -- and their IPv6 equivalents.
#
# Isolated agents (cells: uids 2001-2999) get a second table, inside the
# container's own network namespace. On top of the above, they can't open a
# connection to anything listening in the container itself (T3's API, its
# sshd, your dev servers, a browser's debugging port) except ports
# 20000-29999, which are theirs for their own servers; nor to any private
# address, including the host's. Only the host can change that table: the
# container has no CAP_NET_ADMIN, so not even root in there can lift it.
# The same step hides other users' processes from them (/proc hidepid), so
# they can't read your commands' arguments; dev (gid 1000) still sees all.
#
# Both live in their own nftables tables, so neither ufw nor docker ever
# rewrites them.
#   guard.sh         apply both, once
#   guard.sh watch   apply, then again whenever the container starts (a
#                    restart brings a new network namespace, a recreate a new
#                    bridge). This is what agent-box-guard.service runs.
#   guard.sh off     remove both (make guard-off)
set -eu
NAME=agent-box
NET=agent-box_default
PRIV4="10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16"
PRIV6="fc00::/7, fe80::/10"

host_table() {
  id=$(docker network inspect -f '{{.Id}}' "$NET" 2>/dev/null) || { echo "guard: no $NET network yet"; return 0; }
  name=$(docker network inspect -f '{{index .Options "com.docker.network.bridge.name"}}' "$NET")
  BR=${name:-br-$(echo "$id" | cut -c1-12)}
  # "table ...; delete table ..." first makes re-running idempotent.
  nft -f - <<EOF
table inet agent_box_guard
delete table inet agent_box_guard
table inet agent_box_guard {
  chain input {
    type filter hook input priority filter - 10; policy accept;
    iifname "$BR" ct state established,related accept
    iifname "$BR" tcp dport { 80, 443 } accept
    iifname "$BR" counter drop comment "container -> host"
  }
  chain forward {
    type filter hook forward priority filter - 10; policy accept;
    iifname "$BR" ip daddr { $PRIV4 } counter drop comment "container -> internal"
    # Docker networks are IPv4-only unless you enable IPv6, but if you do:
    # unique-local (incl. Tailscale's fd7a:115c:a1e0::/48 and AWS's metadata
    # at fd00:ec2::254) and link-local.
    iifname "$BR" ip6 daddr { $PRIV6 } counter drop comment "container -> internal v6"
  }
}
EOF
  echo "guard: host table on $BR"
}

cell_table() {
  pid=$(docker inspect -f '{{.State.Pid}}' "$NAME" 2>/dev/null) || pid=0
  [ "$pid" -gt 0 ] || { echo "guard: $NAME is not running"; return 0; }
  # Priority -150: after conntrack, before docker's own NAT (-100), which
  # rewrites the port of its DNS server at 127.0.0.11. Rejecting (rather than
  # dropping) makes a blocked connection fail at once instead of hanging,
  # which is what lets T3 start a cell without waiting for its MCP server.
  nsenter -t "$pid" -n nft -f - <<EOF
table inet agent_box_cells
delete table inet agent_box_cells
table inet agent_box_cells {
  chain output {
    type filter hook output priority -150; policy accept;
    meta skuid 2001-2999 jump cell
  }
  chain cell {
    ct state established,related accept
    oifname "lo" ip daddr 127.0.0.11 meta l4proto { tcp, udp } th dport 53 accept comment "docker's DNS"
    oifname "lo" meta l4proto { tcp, udp } th dport 20000-29999 accept comment "cells' own servers"
    oifname "lo" meta l4proto tcp counter reject with tcp reset comment "cell -> the container itself"
    oifname "lo" counter reject
    ip daddr { $PRIV4 } meta l4proto tcp counter reject with tcp reset comment "cell -> private, incl. the host"
    ip daddr { $PRIV4 } counter reject
    ip6 daddr { $PRIV6 } counter reject
  }
}
EOF
  nsenter -t "$pid" -m mount -o remount,hidepid=invisible,gid=1000 /proc
  # Folders shared read-only with a cell (make cell-share): read-only in here too.
  "$(dirname "$(readlink -f "$0")")/../cells/host-share" ro-inside || true
  echo "guard: cell table and hidden processes in $NAME (pid $pid)"
}

apply() { host_table; cell_table; }

case ${1-} in
  watch)
    since=$(date +%s)
    apply
    # --since replays any start that happened while apply ran. If dockerd
    # restarts, this pipe ends and systemd starts the service again.
    docker events --since "$since" --filter "container=$NAME" --filter event=start --format '{{.Action}}' |
      while read -r _; do apply; done
    ;;
  off)
    nft delete table inet agent_box_guard 2>/dev/null || true
    pid=$(docker inspect -f '{{.State.Pid}}' "$NAME" 2>/dev/null) || pid=0
    if [ "$pid" -gt 0 ]; then
      nsenter -t "$pid" -n nft delete table inet agent_box_cells 2>/dev/null || true
      nsenter -t "$pid" -m mount -o remount,hidepid=off /proc 2>/dev/null || true
    fi
    echo "guard: off (isolated agents now refuse to start)"
    ;;
  *) apply ;;
esac
