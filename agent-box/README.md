# agent-box

A Docker container running **Claude Code, Codex and T3 Code** on a VPS. You
reach it over SSH, and T3's web UI sits behind nginx at `https://code.example.com`.

The idea: agents get a full dev box with sudo, but **inside a container** with
capped RAM/CPU, no Docker socket, and no new ports open to the internet.
Everything you care about (home dir, data, logins, history) is on the host, so
rebuilding the container loses nothing.

```
internet ──443──> nginx (TLS + client cert or password) ──> 127.0.0.1:3773  T3 web UI
         ──22───> host sshd ──ProxyJump──────────────────> 127.0.0.1:2222  container sshd
                                                                  │
                                         agent-box container ─────┘
                                         user `dev` (uid 1000, sudo)
                                         claude, codex, t3, gh, zsh+p10k
                                         /home/dev  <- /srv/agent-box/home
                                         /data      <- /srv/agent-box/data
```

## Setup

On a fresh Ubuntu/Debian VPS with Docker, nginx, certbot and fail2ban installed:

```sh
git clone https://github.com/nickypro/.vps-dotfiles && cd .vps-dotfiles/agent-box

# 1. Storage. The host user that owns it should be uid 1000, like `dev` inside.
sudo mkdir -p /srv/agent-box/{home,data} && sudo chown -R 1000:1000 /srv/agent-box

# 2. Who can SSH in.
cp authorized_keys.example authorized_keys && $EDITOR authorized_keys

# 3. Build and start.
make rebuild && make doctor

# 4. Web UI: set your domain in nginx/agent-box.conf, then
sudo certbot certonly --nginx -d code.example.com
sudo make ca                          # private CA for client certs (once)
sudo make cert NAME_ARG=laptop        # .p12 to import into your browser
sudo make web-passwd USER_ARG=me      # password fallback for devices without a cert
sudo make host-config                 # symlink nginx + fail2ban config, reload
make pair DOMAIN=code.example.com     # T3 pairing link
```

Then log in to the agents once from inside the box (`ssh agent-box`, then
`claude`, `codex login`, `gh auth login`). The logins live in `/home/dev`, so
they survive rebuilds.

Also worth doing on the host: `ufw` allowing only 22/80/443, key-only SSH
(`PasswordAuthentication no`), and some swap.

## Client SSH config

The container's sshd is only on the host's loopback, so you jump through the
host's own sshd:

```
Host myvps
  HostName vps.example.com
  User you

Host agent-box
  HostName 127.0.0.1
  Port 2222
  User dev
  HostKeyAlias agent-box
  ProxyJump myvps
```

`HostKeyAlias` stops the container's key being filed as `[127.0.0.1]:2222`,
which collides with anything else you reach on that port.

## Common tasks

```sh
make help          # list everything
make status        # container + t3 + nginx + fail2ban
make doctor        # verify the things that have broken before
make rebuild       # rebuild image, recreate container
make t3-restart    # restart T3 without dropping SSH sessions
make cert NAME_ARG=phone   # client cert for a new device
```

Updating the agent CLIs without a rebuild:
`sudo npm i -g @anthropic-ai/claude-code@latest @openai/codex@latest t3@latest`,
then `make t3-restart`.

## Secrets

Don't put API keys in `~/.zshrc`; it ends up in backups and screenshares. Put
them in `~/.env` (mode 0600, `KEY=value` lines). The seeded `.zshrc` loads it.

## Things that bit us (don't undo these)

- **`UsePAM yes` in the container's sshd config is required.** `dev` has no
  password (locked), and with PAM off OpenSSH rejects locked accounts as
  *"invalid user"*, which is a very misleading error.
- **SSH host keys are bind-mounted** from `ssh_host_keys/`. In the image they
  would be regenerated on every rebuild, giving a "REMOTE HOST IDENTIFICATION
  HAS CHANGED" warning each time and training you to ignore it.
- **oh-my-zsh lives in `/opt`, not `/home/dev`.** The home dir is a bind
  mount, so anything the image writes there is hidden at runtime. Only the
  `.zshrc` is seeded into the volume, once, and never overwritten.
- **`npm install` needs `--allow-scripts=msgpackr-extract,node-pty`.** npm 11
  blocks install scripts by default; without it node-pty silently fails to
  build and T3's terminals don't work. The Dockerfile checks the build.
- **T3 must listen on `0.0.0.0` inside the container.** If it's on
  `127.0.0.1`, Docker's port publish can't reach it and nginx returns 502s.
  This happens if T3's desktop SSH launcher starts its own server because the
  tmux one died. `make doctor` checks for it; fix with `make t3-restart`.
- **`make t3-restart` also kills stray `t3 serve` processes.** Killing the
  tmux session alone can leave the old server orphaned and holding the port.
- **sshd is PID 1, and T3 runs in tmux.** Restarting T3 never drops SSH.
- **fail2ban `mode = normal` is pinned on purpose.** Normal mode ignores
  failed *publickey* attempts, so offering several keys never bans you;
  `aggressive` mode counts them.
- **No Docker socket in the container.** An agent that can reach dockerd is
  effectively root on the host.
- **Keep exactly one copy of the CA key.** Two copies with separate `ca.srl`
  files would issue duplicate serial numbers.
