#!/bin/sh
set -eu

# --- SSH host keys -------------------------------------------------------
# Kept on a bind mount, NOT in the image: otherwise every rebuild issues a new
# host key and every client gets a "REMOTE HOST IDENTIFICATION HAS CHANGED"
# warning, which trains you to ignore the one warning that matters.
mkdir -p /etc/ssh/host_keys
[ -f /etc/ssh/host_keys/ssh_host_ed25519_key ] || \
  ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/host_keys/ssh_host_ed25519_key
[ -f /etc/ssh/host_keys/ssh_host_rsa_key ] || \
  ssh-keygen -q -t rsa -b 4096 -N '' -f /etc/ssh/host_keys/ssh_host_rsa_key
chmod 600 /etc/ssh/host_keys/ssh_host_*_key

# --- home directory ------------------------------------------------------
# /home/dev is a bind mount from the host.
mkdir -p /home/dev
chown dev:dev /home/dev 2>/dev/null || true
install -d -m 700 -o dev -g dev /home/dev/.ssh   2>/dev/null || true
install -d -m 755 -o dev -g dev /home/dev/.cache 2>/dev/null || true

mkdir -p /run/sshd

# Seed the shell config on first start only. The bind mount hides anything the
# image put in /home/dev, and we must never clobber edits made on the volume.
if [ ! -f /home/dev/.zshrc ]; then
  cp /etc/skel-zsh/.zshrc /home/dev/.zshrc
  chown dev:dev /home/dev/.zshrc
  echo "entrypoint: seeded /home/dev/.zshrc"
fi

# --- isolated agents ----------------------------------------------------
# Their users live in the image layer, which a rebuild replaces: recreate
# them from /cells/*/.cell (on the host volume) before anything can start one.
/opt/agent-box/cells/cell-admin sync || echo "entrypoint: warning - cell-admin sync failed" >&2

# --- services ------------------------------------------------------------
# T3 runs in a tmux session; sshd is PID 1. A T3 crash or restart therefore
# never drops your SSH sessions. t3-serve loads ~/.env and the PATH T3 needs.
su dev -s /bin/sh -c 'tmux has-session -t t3 2>/dev/null || tmux new-session -d -s t3 "/opt/agent-box/bin/t3-serve 2>&1 | tee -a /home/dev/.t3-serve.log"' \
  || echo "entrypoint: warning - could not start the t3 tmux session" >&2

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config_box
