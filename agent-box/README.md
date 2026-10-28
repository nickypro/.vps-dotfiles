# agent-box

A Docker container running **Claude Code, Codex and T3 Code** on a VPS. You
reach it over SSH, and T3's web UI over Tailscale (or, if you prefer, behind
nginx on a public domain).

The idea: agents get a full dev box with sudo, but **inside a container** with
capped RAM/CPU, no Docker socket, and no new ports open to the internet.
Everything you care about (home dir, data, logins, history) is on the host, so
rebuilding the container loses nothing.

```
your devices ──tailnet──> tailscale serve :443 ──┐
internet ──443──> nginx (ACCESS=mtls|public) ────┴──> 127.0.0.1:3773  T3 web UI
internet ──22───> host sshd ──ProxyJump─────────────> 127.0.0.1:2222  container sshd
                                                             │
                                    agent-box container ─────┘
                                    user `dev` (uid 1000, sudo)
                                    claude, codex, t3, gh, zsh+p10k
                                    /home/dev  <- /srv/agent-box/home
                                    /data      <- /srv/agent-box/data
```

## Pick how you reach the web UI

T3's web UI is effectively a terminal with sudo in the container, so who can
reach it matters. One setting, `ACCESS` in `config.mk`:

- **`tailscale`** (the default, recommended). Only your own devices, over your
  [tailnet](https://tailscale.com) (Tailscale's private network between your
  machines). No domain, no certs, no nginx, nothing open to the internet.
  `tailscale serve` gives the box an HTTPS address like
  `https://myvps.your-tailnet.ts.net` that only your tailnet can see.
- **`mtls`**. A public domain via nginx + Let's Encrypt. The browser must
  present a client certificate from your own private CA ("mutual TLS"); an
  optional password covers devices without one.
- **`public`**. A public domain via nginx, password only, with per-IP rate
  limiting and fail2ban banning IPs that guess wrong.

In every mode, T3's own pairing token (`make pair`) still applies on top.

> **About `public`:** in this mode a single password is all that keeps the
> internet out of a terminal with sudo in your container (and the agents'
> logins). The password is generated rather than chosen, and guessing is
> slowed and banned, but it is still one secret. If you can install Tailscale
> on your devices, use `tailscale`.

To switch later, edit `config.mk` and run `sudo make host-config` again. It
removes the other modes' pieces (the nginx site, or the `tailscale serve`).

## Setup

On a fresh Ubuntu/Debian VPS with Docker and fail2ban installed:

```sh
git clone https://github.com/nickypro/.vps-dotfiles && cd .vps-dotfiles/agent-box

# 1. Storage. The host user that owns it should be uid 1000, like `dev` inside.
sudo mkdir -p /srv/agent-box/{home,data} && sudo chown -R 1000:1000 /srv/agent-box

# 2. Who can SSH in.
cp authorized_keys.example authorized_keys && $EDITOR authorized_keys

# 3. Build and start, then fence the container off the host (see Network guard).
make rebuild && sudo make guard-link && make net-test && make doctor
```

Then the web UI, depending on `ACCESS`.

**tailscale** (also needs `jq`, which the Makefile uses to look up the box's
tailnet name):

```sh
curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up
sudo make host-config      # runs: tailscale serve --bg --https=443 http://127.0.0.1:3773
make pair                  # T3 pairing link
```

- HTTPS on a tailnet needs **MagicDNS** and **HTTPS Certificates** turned on
  (admin console, DNS page). If they're off, the first `tailscale serve`
  prints a link to turn them on.
- Machine names end up in public certificate logs, so don't name the box
  anything secret.
- In the admin console, **disable key expiry** for the box (Machines, the
  `...` menu). Otherwise it drops off your tailnet when its key expires.
- Use `tailscale serve`, never `tailscale funnel`: Funnel publishes to the
  whole internet. `make doctor` warns if it's on.
- "Your tailnet only" means everyone on it. If other people are on your
  tailnet (a team, or a device someone shared with you), add a rule to the
  tailnet's access policy (admin console, Access controls) so only you can
  reach this machine.

**mtls** (needs nginx and certbot). Set `ACCESS = mtls` and `DOMAIN` in
`config.mk`, and your domain in `nginx/agent-box-mtls.conf`, then:

```sh
sudo certbot certonly --nginx -d code.example.com
sudo make ca                          # private CA for client certs (once)
sudo make cert NAME_ARG=laptop        # .p12 to import into your browser
sudo make web-passwd USER_ARG=me      # optional password for devices without a cert
sudo make host-config                 # link nginx + fail2ban config, reload
make pair                             # T3 pairing link
```

Lost a device, or done with a cert? `sudo make cert-revoke NAME_ARG=laptop`
and nginx refuses it from then on (`make client-cert-list` shows which are
revoked). Each name gets one cert, so a replacement needs a new name, like
`laptop-2`.

If a device says the `.p12` password is wrong when it isn't, it may not read
OpenSSL 3's newer encryption: export it again with `openssl pkcs12 -export
-legacy ...`, using the same `.key` and `.crt`.

**public** (needs nginx and certbot). Set `ACCESS = public` and `DOMAIN` in
`config.mk`, and your domain in `nginx/agent-box-public.conf`, then:

```sh
sudo certbot certonly --nginx -d code.example.com
sudo make web-passwd USER_ARG=me      # required; prints a generated password
sudo make host-config                 # link nginx + fail2ban config, reload
make pair                             # T3 pairing link
```

Then log in to the agents once from inside the box (`ssh agent-box`, then
`claude`, `codex login`, `gh auth login`). The logins live in `/home/dev`, so
they survive rebuilds.

Also worth doing on the host: `ufw` allowing only 22 (plus 80/443 for `mtls`
and `public`), key-only SSH (`PasswordAuthentication no`), and some swap.

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
  ForwardAgent no
```

`HostKeyAlias` stops the container's key being filed as `[127.0.0.1]:2222`,
which collides with anything else you reach on that port.

`ForwardAgent no` matters if you have `ForwardAgent yes` anywhere else: every
agent has sudo in the box, so any of them could use a forwarded agent to log
in as you wherever your keys work. The container's sshd refuses forwarding
too, but this keeps your client from offering it. (For GitHub, use `gh auth
login` inside the box instead.)

The box only reads keys from `./authorized_keys` on the host, never from
`~/.ssh/authorized_keys` inside it, so an agent can't add a key of its own,
and deleting a line really does revoke that key.

### The T3 desktop and phone apps

The desktop app can connect over SSH: add `agent-box` as an SSH host and it
picks up the T3 server already running in tmux, so the web UI, the desktop
app and your phone all see the same threads. On a phone, open the pairing
link from `make pair LABEL=phone` (over your tailnet, in tailscale mode).

### Closing public SSH (tailscale mode, optional)

With Tailscale up, SSH can go over the tailnet too, and port 22 can stop
facing the internet. This is plain SSH, just over the tailnet: your keys,
fail2ban and the config above stay the same; only `HostName` changes. (You
don't need Tailscale SSH for this.)

1. Set `HostName myvps.your-tailnet.ts.net` (or the box's `100.x.y.z` address
   from `tailscale ip -4`) in the `myvps` block. **Check that both `ssh myvps`
   and `ssh agent-box` work this way before going on.**
2. Make sure key expiry is disabled for the box (see above), and that you know
   your way back in without SSH (your provider's web console).
3. Then, on the host:

   ```sh
   sudo ufw allow in on tailscale0
   sudo ufw delete allow OpenSSH       # or 22/tcp: match how you added it
   sudo ufw status                     # no rule for 22 should be left
   ```

## Common tasks

```sh
make help          # list everything
make status        # container + t3 + web access + fail2ban
make doctor        # verify the things that have broken before
make update        # latest claude, codex and t3, in place, then restart T3
make rebuild       # fresh base image + latest CLIs, recreate the container
make t3-restart    # restart T3 without dropping SSH sessions
make pair LABEL=phone           # T3 pairing link for one more device
make cert NAME_ARG=phone        # mtls: client cert for a new device
make cert-revoke NAME_ARG=phone # mtls: refuse that cert from now on
```

`make update` is quick but lives in the container's own layer, which a
recreate throws away. `make rebuild` re-downloads the base image (security
fixes) and the CLIs (at most once a day), so it never rolls you back.

## Backups (Kopia to Backblaze B2)

Optional, but cheap. Hourly, encrypted, off-site, and **undeletable for 14
days**, even by you.

- **It runs on the host, not in the container.** Agents have sudo inside the
  container, but they can't see `/root/backup/b2.env` on the host, so no agent
  can reach the backup credentials or delete a backup.
- **Kopia, not restic**, because restic doesn't support Object Lock. Kopia
  locks every file it uploads and keeps extending the locks.
- **Object Lock in compliance mode** means nobody, including the B2 account
  owner, can delete a locked file before its lock runs out. Kopia locks each
  file for 14 days, and its full maintenance (daily) re-extends the lock on
  everything still in use. So full maintenance must run more often than every
  14 days; kopia schedules it itself, after snapshots.
- **Each snapshot is complete on its own.** Kopia cuts files into chunks by
  content and stores each chunk once (deduplication), so an hourly run only
  uploads new chunks, and pruning an old snapshot never breaks another one.
- **What's backed up:** `/srv/agent-box` (home dir, agent logins, `/data`),
  this directory (`authorized_keys`, `ssh_host_keys/`), `/etc` and `/root`.
  Edit `SOURCES` at the top of `backup/agent-box-backup`. Skipped everywhere:
  `.cache/`, `node_modules/`, `__pycache__/`, `.Trash*/`; also the backup
  credentials.
- **The container's own filesystem too**, as source
  `root@<host>:/agent-box-container`: whatever was installed or changed inside
  the container since the image was built (a live `apt install`, its `/etc`).
  That's the overlay's "upperdir", whose path changes every time the container
  is recreated, hence the fixed `--override-source` name. Kopia applies the
  policy of that name, so its skips (below) go there. Don't point kopia at
  `/proc/<pid>/root` instead: kopia follows a symlinked source, and that one
  leads to the *host's* `/`.
- **Each run also checks** that `/` and `/srv/agent-box` are under 90% full,
  and once a week downloads ~1% of the backed-up files to prove they still
  decrypt and match (`kopia snapshot verify`). Either failing fails the run.
- **Retention:** latest 10, 48 hourly, 30 daily, 8 weekly, 12 monthly, 2 yearly.

### 1. The bucket (Backblaze web UI)

1. Sign up for B2. The signup form is an iframe that ad blockers can hide: if
   the page looks empty, turn the blocker off for it.
2. Create a bucket: **Private**, with **Object Lock enabled** when you create
   it. No default retention: Kopia sets retention on each file itself.
3. Lifecycle settings, custom rule:
   `{"fileNamePrefix":"","daysFromHidingToDeleting":15}`. When Kopia prunes a
   file, B2 only hides it; this deletes hidden files 15 days later so they
   stop costing money. 15, not 1, so nothing is purged while still locked.
4. App keys: add one restricted to **this bucket only**, with **read and
   write** access. Note the keyID and applicationKey (shown once), and the
   bucket's endpoint, `s3.<region>.backblazeb2.com`.

### 2. The repository (as root on the host)

Install kopia ([kopia.io/docs/installation](https://kopia.io/docs/installation/)), then:

```sh
mkdir -p /root/backup && chmod 700 /root/backup
cat > /root/backup/b2.env <<'EOF'
B2_KEY_ID=<keyID>
B2_APP_KEY=<applicationKey>
KOPIA_PASSWORD=<long and random, e.g. from: openssl rand -hex 32>
# Optional, see Alerts below:
# HC_URL=https://hc-ping.com/<uuid>
EOF
chmod 600 /root/backup/b2.env

set -a; . /root/backup/b2.env; set +a
export AWS_ACCESS_KEY_ID="$B2_KEY_ID" AWS_SECRET_ACCESS_KEY="$B2_APP_KEY"
kopia repository create s3 --bucket=<bucket> --endpoint=s3.<region>.backblazeb2.com --region=<region> \
  --retention-mode=COMPLIANCE --retention-period=14d --description="agent-box backup"
kopia maintenance set --extend-object-locks true
kopia policy set --global --keep-latest 10 --keep-hourly 48 --keep-daily 30 --keep-weekly 8 --keep-monthly 12 --keep-annual 2 \
  --compression zstd-fastest --add-ignore ".cache/" --add-ignore "node_modules/" --add-ignore "__pycache__/" --add-ignore ".Trash*/"
kopia policy set /root --add-ignore "/backup/" --add-ignore "/.config/kopia/"
# The container's own files: skip agent scratch and caches.
kopia policy set "root@$(hostname):/agent-box-container" \
  --add-ignore "/tmp/" --add-ignore "/var/tmp/" --add-ignore "/var/cache/" --add-ignore "/root/.npm/"
# mtls mode, optional: leave the client-cert CA out, so its key stays single-copy.
kopia policy set /etc --add-ignore "/nginx/agent-box/"

cd /path/to/agent-box
make backup-link     # script + systemd units, enables the hourly timer
make backup-now      # first run now; it can take hours
```

**The repository password is the only way to decrypt the backups.** Put it in
your password manager now. `b2.env` itself is not backed up.

### Alerts (optional, but do it)

The 14-day lock only helps if you notice a problem within 14 days, and a
backup that quietly stopped looks exactly like one that works. Make a check at [healthchecks.io](https://healthchecks.io) with a 1 hour
period (grace: a few hours, for the first long upload) and put its ping URL
in `b2.env` as `HC_URL`. The script pings it when it starts and when it ends,
so a missed or failed backup, a nearly full disk or a failed read-back sends
you an email. On failure the reason goes in the ping body, which healthchecks
puts in the email.

### Day to day

```sh
sudo make backup-status    # running? next run? latest snapshots
sudo make backup-now       # start one now, in the background
journalctl -u agent-box-backup -n 50
```

### Restore (as root on the host)

```sh
kopia snapshot list --all                        # find a snapshot ID
kopia ls -l <snapshot-id>/some/folder            # browse it
kopia restore <snapshot-id>/some/folder /tmp/restored
kopia mount <snapshot-id> /mnt/kopia &           # or browse it as a filesystem
```

Paths after the ID are relative to that snapshot's source, e.g.
`<snapshot-id>/home/.claude` in a `/srv/agent-box` snapshot.

On a fresh server: install kopia, recreate `/root/backup/b2.env` (a new B2 app
key, the same repository password), then

```sh
set -a; . /root/backup/b2.env; set +a
kopia repository connect s3 --bucket=<bucket> --endpoint=s3.<region>.backblazeb2.com --region=<region> \
  --access-key="$B2_KEY_ID" --secret-access-key="$B2_APP_KEY"
kopia maintenance set --owner=me    # this host now runs maintenance, which keeps the locks extended
```

If something *hid* files in the bucket (a delete through the S3 API only adds
a hide marker), the locked versions are still there: delete the hide markers
in the B2 web UI ("Show all versions") and Kopia sees them again.

### Things that bit us (backups)

- **`Environment=HOME=/root` in the service is required.** Without it kopia
  can't find its config and says "repository is not connected".
- **Keep `TimeoutStartSec=infinity`.** Without it, systemd killed our first
  multi-hour upload after about two minutes.
- **A running backup shows as `activating`, not `active`.** That's how
  `Type=oneshot` services look while they run, so `make backup-status`
  checks for `activating`.

## Network guard

Agents read web pages and install packages, so assume one will eventually
follow a malicious instruction. The container can still reach the whole
internet (pip, npm, GitHub, APIs all work), but `firewall/guard.sh` stops it
from using the box as a step towards anything else:

- **Dropped:** the host itself (its sshd, databases, other apps) except ports
  80/443; the cloud metadata service at 169.254.169.254 (which on some clouds
  hands out credentials); private ranges 10/8, 172.16/12, 192.168/16; and
  Tailscale's 100.64/10, so in tailscale mode agents can't reach your other
  devices. The IPv6 equivalents (fc00::/7, fe80::/10) too, in case you ever
  turn IPv6 on for the docker network.
- **Unaffected:** traffic the host starts (SSH jump, `tailscale serve`/nginx to
  T3, docker's port publishing). Replies match "established".
- It's its own nftables table (`inet agent_box_guard`), so ufw and docker never
  rewrite or flush it. Needs `nft` (package `nftables`, installed by
  default on current Debian/Ubuntu). `agent-box-guard.service` applies it at boot.
- The rules match the docker bridge name, which changes when compose recreates
  the network. `make up` re-applies the guard and `make doctor` warns if it's
  aimed at an old bridge.

```sh
sudo make guard-link   # install + start (once)
make net-test          # from inside the container: what's open, what's blocked
sudo make guard-off    # lift it until the next boot or `make up`
```

If `make net-test` says DNS is BROKEN, your provider's DNS server is in one
of the blocked ranges (some clouds put it at 169.254.169.253 or in 10/8):
add `dns: [1.1.1.1, 9.9.9.9]` to the service in `docker-compose.yml` and
`make up`.

The container is also capped at 4096 processes (`pids_limit`), so a runaway
agent can't exhaust the host's process table.

## Secrets

Don't put API keys in `~/.zshrc`; it ends up in backups and screenshares. Put
them in `~/.env` (mode 0600, `KEY=value` lines). The seeded `.zshrc` loads it.

Everything in the box, `~/.env` and the agents' own logins included, is
readable by every agent, and an agent can be talked into things by a web page
it reads. So hand them credentials you'd be fine losing:

- **GitHub:** a [fine-grained token](https://github.com/settings/personal-access-tokens)
  for just the repos the agents work on (`gh auth login --with-token`),
  rather than the all-repos login `gh auth login` gives you by default.
- **API keys:** a separate key for the box, with a spending limit set in the
  provider's dashboard.
- **Nothing else:** no cloud admin keys, no SSH keys to other machines.

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
  `127.0.0.1`, Docker's port publish can't reach it and the web UI returns
  502s (from nginx or `tailscale serve`). This happens if T3's desktop SSH
  launcher starts its own server because the tmux one died. `make doctor`
  checks for it; fix with `make t3-restart`.
- **`make t3-restart` also kills stray `t3 serve` processes.** Killing the
  tmux session alone can leave the old server orphaned and holding the port.
- **sshd is PID 1, and T3 runs in tmux.** Restarting T3 never drops SSH.
- **fail2ban `mode = normal` is pinned on purpose.** Normal mode ignores
  failed *publickey* attempts, so offering several keys never bans you;
  `aggressive` mode counts them.
- **sshd reads only the host's `authorized_keys`, and refuses agent
  forwarding.** See "Client SSH config". If you used to keep keys in the
  box's `~/.ssh/authorized_keys`, move them to `./authorized_keys`.
- **`make build` uses `--pull` and a date stamp.** Without them, Docker
  reuses months-old layers: an unpatched base image, and CLIs older than the
  ones `make update` installed.
- **No Docker socket in the container.** An agent that can reach dockerd is
  effectively root on the host.
- **Keep exactly one copy of the CA key** (mtls). Two copies with separate
  `ca.srl` files would issue duplicate serial numbers.
