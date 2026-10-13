#!/bin/sh
# Keep the agent-box container off the host and off internal networks.
#
# The container still reaches the whole internet and the host's 80/443 (so
# agents can fetch your own nginx sites). Dropped: every other host port
# (sshd, databases, other apps), the cloud metadata service (169.254.169.254,
# which on some clouds hands out credentials) and private ranges, including
# Tailscale's 100.64/10 -- so in tailscale mode agents cannot reach your
# other devices.
#
# Lives in its own nftables table, so neither ufw nor docker ever rewrites it.
# The bridge name is derived from the docker network, which compose recreates
# on `make down`/`up` -- so `make up` re-runs this. Undo: make guard-off
set -eu
NET=agent-box_default
id=$(docker network inspect -f '{{.Id}}' "$NET")
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
    iifname "$BR" ip daddr { 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } counter drop comment "container -> internal"
  }
}
EOF
echo "agent-box guard active on $BR"
