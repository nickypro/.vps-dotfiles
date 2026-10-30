# Agent box. Everything here is declarative: the container, the nginx site,
# the fail2ban jails and the backup units all live in this directory and are
# symlinked into place, so `git diff` shows the full state of the deployment.
#
# Settings (how T3 is reached, your domain) are in config.mk.
#
# Uses .RECIPEPREFIX so recipes are indented with ">" instead of tabs.
.RECIPEPREFIX = >
.DEFAULT_GOAL := help
SHELL := /bin/bash

-include config.mk
ACCESS ?= tailscale
ifeq ($(filter $(ACCESS),tailscale ssh mtls public),)
  $(error ACCESS must be one of: tailscale ssh mtls public - see config.mk)
endif

COMPOSE := docker compose
NAME    := agent-box
SRV     := /srv/agent-box
AUTHDIR := /etc/nginx/agent-box

# The web UI's hostname. Tailscale mode looks up this machine's MagicDNS name
# (myvps.your-tailnet.ts.net); the nginx modes take it from config.mk.
ifeq ($(ACCESS),tailscale)
  DOMAIN ?= $(shell tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' 2>/dev/null | sed 's/\.$$//')
endif
DOMAIN ?= code.example.com

.PHONY: help build up down restart rebuild update logs shell t3-logs t3-restart pair secret \
        claude-account claude-accounts claude-account-rm \
        cell cells cell-share cell-unshare cell-rm \
        host-config host-config-tailscale host-config-ssh host-config-mtls host-config-public fail2ban-config \
        ca cert cert-revoke client-cert-list web-passwd \
        backup-link backup-status backup-now \
        guard-link guard-off net-test \
        status status-tailscale status-ssh status-mtls status-public ps \
        doctor doctor-tailscale doctor-ssh doctor-mtls doctor-public

help:  ## Show this help
> @grep -hE '^[a-z0-9-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}'
> @echo "  ACCESS=$(ACCESS) (config.mk)"

## --- container ----------------------------------------------------------
build:  ## Build the image (fresh base image, today's agent CLIs)
> @# --pull picks up the base image's security fixes; the date re-runs the
> @# npm layer at most once a day, so the CLIs are current too.
> $(COMPOSE) build --pull --build-arg AGENTS_STAMP=$$(date +%F) --build-arg EXTRAS="$(EXTRAS)"

up:  ## Start (or recreate) the container
> @test -f authorized_keys || { echo "create ./authorized_keys first (see authorized_keys.example)"; exit 1; }
> mkdir -p ssh_host_keys
> @test -d $(SRV)/cells || mkdir -p $(SRV)/cells || { echo "  create $(SRV)/cells first: sudo mkdir $(SRV)/cells"; exit 1; }
> $(COMPOSE) up -d
> @# compose may have recreated the network (new bridge name), so re-aim the guard.
> @systemctl restart agent-box-guard 2>/dev/null && echo "  network guard re-applied" || echo "  network guard NOT re-applied: sudo systemctl restart agent-box-guard (first time: sudo make guard-link)"

down:  ## Stop and remove the container (volume data is untouched)
> $(COMPOSE) down

restart:  ## Restart the container
> $(COMPOSE) restart

rebuild: build up  ## Rebuild the image and recreate the container

update:  ## Update claude, codex and t3 in place (no rebuild), then restart T3
> @# Same --allow-scripts as the Dockerfile: npm 11 skips install scripts
> @# otherwise, and Claude Code's sets up its native binary.
> docker exec $(NAME) npm install -g --allow-scripts=@anthropic-ai/claude-code,msgpackr-extract,node-pty \
   @anthropic-ai/claude-code@latest @openai/codex@latest t3@latest
> @# As dev: the first run of a new t3 downloads its binary into ~/.t3/runtime.
> @docker exec -u dev -e HOME=/home/dev $(NAME) sh -c 'echo "  claude $$(claude --version)"; echo "  codex  $$(codex --version)"; echo "  t3     $$(t3 --version)"'
> @$(MAKE) --no-print-directory t3-restart

logs:  ## Follow container logs (sshd)
> docker logs -f --tail 100 $(NAME)

shell:  ## Root shell inside the container (from the host)
> docker exec -it $(NAME) zsh

## --- the T3 server ------------------------------------------------------
t3-logs:  ## Tail the T3 server log
> docker exec $(NAME) tail -n 80 -f /home/dev/.t3-serve.log

t3-restart:  ## Restart just T3, without dropping SSH sessions
> docker exec $(NAME) su dev -s /bin/sh -c 'tmux kill-session -t t3 2>/dev/null; true'
> @# Killing tmux can leave the old server orphaned and holding the port.
> -docker exec -u dev $(NAME) pkill -f "t3 serve"
> docker exec -d $(NAME) su dev -s /bin/sh -c 'tmux new-session -d -s t3 "/opt/agent-box/bin/t3-serve 2>&1 | tee -a /home/dev/.t3-serve.log"'
> @sleep 3 && curl -sf -o /dev/null -w "  t3 http: %{http_code}\n" http://127.0.0.1:3773/ || echo "  t3 not responding yet"

pair:  ## Mint a T3 pairing token for the web UI (30 min):  make pair LABEL=phone
> @test "$(ACCESS)" != ssh || { echo "  no web UI in ssh mode: the T3 app pairs itself when you add agent-box as an SSH host"; exit 1; }
> @test -n "$(DOMAIN)" || { echo "  no DOMAIN: is tailscale up and jq installed? Or set DOMAIN in config.mk"; exit 1; }
> @docker exec $(NAME) su dev -s /bin/sh -c 't3 auth pairing create --ttl 30m --label $(or $(LABEL),laptop) --base-url https://$(DOMAIN)' | grep -aE 'Token:|Pair URL:|Expires' || true

secret:  ## Save an API key for the agents (asks for it, hidden):  make secret KEY=OPENAI_API_KEY [CELL=web]
> @test -n "$(KEY)" || { echo "usage: make secret KEY=<NAME> [CELL=<cell>]"; exit 1; }
> @read -rsp "  value for $(KEY) (not shown): " v && echo && \
   docker exec -i $(NAME) /opt/agent-box/bin/set-secret "$(KEY)" $(CELL) <<< "$$v"
> @test -n "$(CELL)" || echo "  make t3-restart, so agents T3 starts see it too"

## --- more Claude logins (see README) -----------------------------------
# EMAIL only from the command line: some shells set EMAIL for other tools.
LOGIN_EMAIL = $(if $(filter command line,$(origin EMAIL)),$(EMAIL))
claude-account:  ## Another Claude login, its own provider in T3:  make claude-account ACCOUNT=work [LABEL=Work] [COLOR=15803d]
> @test -n "$(ACCOUNT)" || { echo "usage: make claude-account ACCOUNT=<name> [LABEL=<name in T3>] [COLOR=rrggbb] [EMAIL=<login>]"; exit 1; }
> @t=; [ -t 0 ] && t=-t; docker exec -i $$t -u dev -e HOME=/home/dev -e EMAIL="$(LOGIN_EMAIL)" $(NAME) \
   /opt/agent-box/bin/claude-account add "$(ACCOUNT)" "$(LABEL)" "$(COLOR)"

claude-accounts:  ## List the Claude logins, their names in T3 and who is logged in
> @docker exec -u dev -e HOME=/home/dev $(NAME) /opt/agent-box/bin/claude-account list

claude-account-rm:  ## Take a Claude login out of T3 (its folder and login stay):  make claude-account-rm ACCOUNT=work
> @test -n "$(ACCOUNT)" || { echo "usage: make claude-account-rm ACCOUNT=<name>"; exit 1; }
> docker exec -u dev -e HOME=/home/dev $(NAME) /opt/agent-box/bin/claude-account rm "$(ACCOUNT)"

## --- isolated agents ("cells"; see README) -----------------------------
cell:  ## New isolated agent: own user + folder, own providers in T3:  make cell CELL=web
> @test -n "$(CELL)" || { echo "usage: make cell CELL=<name>"; exit 1; }
> docker exec -u root $(NAME) /opt/agent-box/cells/cell-admin add $(CELL)

cells:  ## List isolated agents, their logins and shared folders
> @docker exec -u root $(NAME) /opt/agent-box/cells/cell-admin list

# AS= names the share. make has a built-in AS (the assembler, "as"), so only
# take it when you set it yourself.
SHARE_AS = $(if $(filter command line environment,$(origin AS)),$(AS))
cell-share:  ## Show it a folder, read-only unless RW=1:  sudo make cell-share CELL=web DIR=/data/papers
> @test -n "$(CELL)" -a -n "$(DIR)" || { echo "usage: sudo make cell-share CELL=<cell> DIR=<folder> [AS=<name>] [RW=1]"; exit 1; }
> $(CURDIR)/cells/host-share share $(CELL) "$(DIR)" "$(SHARE_AS)" "$(or $(RW),0)"
> @docker exec $(NAME) test -d /cells/$(CELL)/shared/$(or $(SHARE_AS),$(notdir $(patsubst %/,%,$(DIR)))) \
   && echo "  visible in the box now" || echo "  not visible inside yet: make up (the /cells volume needs propagation: rslave)"

cell-unshare:  ## Stop sharing a folder with it:  sudo make cell-unshare CELL=web DIR=papers
> @test -n "$(CELL)" -a -n "$(DIR)" || { echo "usage: sudo make cell-unshare CELL=<cell> DIR=<name>"; exit 1; }
> $(CURDIR)/cells/host-share unshare $(CELL) "$(DIR)"

cell-rm:  ## Remove its user and T3 providers (its files stay):  make cell-rm CELL=web
> @test -n "$(CELL)" || { echo "usage: make cell-rm CELL=<name>"; exit 1; }
> docker exec -u root $(NAME) /opt/agent-box/cells/cell-admin rm $(CELL)

## --- web access: host side (ACCESS in config.mk) ------------------------
host-config: host-config-$(ACCESS) fail2ban-config  ## Set up web access for ACCESS, plus fail2ban

# Each mode removes the other modes' pieces (after its own checks pass), so
# switching is just "edit config.mk, run sudo make host-config again".
UNLINK_NGINX := rm -f /etc/nginx/sites-enabled/agent-box*.conf /etc/fail2ban/jail.d/agent-box-nginx.local
# An empty client-cert revocation list (mtls), included by nginx.
NEW_REVOKED_MAP := printf '%s\n' '\# Revoked client-cert serials, one per line: <SERIAL> 1;' '\# Appended by: make cert-revoke NAME_ARG=<device>' > $(AUTHDIR)/revoked.map

host-config-tailscale:
> @tailscale status >/dev/null 2>&1 || { echo "  tailscale is not up: sudo tailscale up"; exit 1; }
> @# --bg keeps serving across reboots and tailscaled restarts. The first time,
> @# it may print a link to turn on HTTPS certificates for your tailnet.
> tailscale serve --bg --https=443 http://127.0.0.1:3773
> @# No nginx in this mode: drop any agent-box site an nginx mode left behind.
> $(UNLINK_NGINX)
> @if systemctl is-active -q nginx; then nginx -t && systemctl reload nginx; fi
> @echo "  web UI: https://$(DOMAIN)  (your tailnet only)"

host-config-ssh:
> @# No web UI: take down whatever another mode left serving T3.
> $(UNLINK_NGINX)
> @if systemctl is-active -q nginx; then nginx -t && systemctl reload nginx; fi
> @command -v tailscale >/dev/null && tailscale serve --https=443 http://127.0.0.1:3773 off >/dev/null 2>&1; true
> @echo "  no web UI: in the T3 app, add agent-box (your ~/.ssh/config) as an SSH host"

host-config-mtls host-config-public: host-config-%:
> @test "$(DOMAIN)" != code.example.com || { echo "  set DOMAIN in config.mk first"; exit 1; }
> @grep -q "server_name $(DOMAIN);" nginx/agent-box-$*.conf || { echo "  put $(DOMAIN) in nginx/agent-box-$*.conf first (server_name and cert paths)"; exit 1; }
> @test -f /etc/letsencrypt/live/$(DOMAIN)/fullchain.pem || { echo "  no TLS cert yet: sudo certbot certonly --nginx -d $(DOMAIN)"; exit 1; }
> @test $* != mtls   || test -f $(AUTHDIR)/ca.crt   || { echo "  no client CA yet: sudo make ca"; exit 1; }
> @# nginx refuses to start if the revocation list it includes is missing
> @# (e.g. a CA made before cert-revoke existed).
> @test $* != mtls   || test -f $(AUTHDIR)/revoked.map || $(NEW_REVOKED_MAP)
> @test $* != public || test -f $(AUTHDIR)/htpasswd || { echo "  public mode needs a password first: sudo make web-passwd USER_ARG=me"; exit 1; }
> $(UNLINK_NGINX)
> ln -sfn $(CURDIR)/nginx/agent-box-$*.conf /etc/nginx/sites-enabled/agent-box-$*.conf
> ln -sfn $(CURDIR)/fail2ban/nginx-http-auth.local /etc/fail2ban/jail.d/agent-box-nginx.local
> nginx -t && systemctl reload nginx
> @# Coming from tailscale mode: stop serving T3 on the tailnet as well.
> @command -v tailscale >/dev/null && tailscale serve --https=443 http://127.0.0.1:3773 off >/dev/null 2>&1; true
> @echo "  web UI: https://$(DOMAIN)"

fail2ban-config:
> ln -sfn $(CURDIR)/fail2ban/jail.local /etc/fail2ban/jail.local
> fail2ban-client -t && systemctl restart fail2ban
> @echo "  host config applied (ACCESS=$(ACCESS))"

## --- mtls / public: client certs and passwords --------------------------
ca:  ## mtls: create the private CA for client certs (once)
> @test "$(ACCESS)" = mtls || { echo "  client certs are for ACCESS=mtls (config.mk has $(ACCESS))"; exit 1; }
> @test ! -e $(AUTHDIR)/ca.key || { echo "CA already exists in $(AUTHDIR)"; exit 1; }
> mkdir -p $(AUTHDIR) && cd $(AUTHDIR) && umask 077 && \
   openssl req -x509 -newkey rsa:4096 -nodes -keyout ca.key -out ca.crt \
     -days 3650 -subj "/CN=agent-box client CA" 2>/dev/null && chmod 644 ca.crt
> @$(NEW_REVOKED_MAP)
> @echo "  CA written to $(AUTHDIR) - keep exactly one copy of ca.key"

cert:  ## mtls: issue a client cert for a device:  make cert NAME_ARG=firefox
> @test "$(ACCESS)" = mtls || { echo "  client certs are for ACCESS=mtls (config.mk has $(ACCESS))"; exit 1; }
> @test -n "$(NAME_ARG)" || { echo "usage: make cert NAME_ARG=<device>"; exit 1; }
> @# Reissuing under the same name would overwrite the old .crt, and with it
> @# the only record of the serial that cert-revoke needs.
> @test ! -e $(AUTHDIR)/$(NAME_ARG).crt || { echo "  $(NAME_ARG) already has a cert: pick a new name (e.g. $(NAME_ARG)-2), or cert-revoke the old one first"; exit 1; }
> @cd $(AUTHDIR) && umask 077 && \
   PASS=$$(openssl rand -base64 18 | tr -d '/+=' | head -c 20) && \
   openssl genrsa -out $(NAME_ARG).key 2048 2>/dev/null && \
   openssl req -new -key $(NAME_ARG).key -subj "/CN=$(NAME_ARG)" -out $(NAME_ARG).csr 2>/dev/null && \
   openssl x509 -req -in $(NAME_ARG).csr -CA ca.crt -CAkey ca.key -CAcreateserial \
     -out $(NAME_ARG).crt -days 825 -sha256 2>/dev/null && \
   openssl pkcs12 -export -out $(NAME_ARG).p12 -inkey $(NAME_ARG).key -in $(NAME_ARG).crt \
     -certfile ca.crt -name "agent-box ($(NAME_ARG))" -passout pass:$$PASS 2>/dev/null && \
   rm -f $(NAME_ARG).csr && \
   echo "  wrote $(AUTHDIR)/$(NAME_ARG).p12   password: $$PASS" && \
   echo "  copy it off, then: rm $(AUTHDIR)/$(NAME_ARG).p12 $(AUTHDIR)/$(NAME_ARG).key"

cert-revoke:  ## mtls: revoke a device's client cert:  make cert-revoke NAME_ARG=phone
> @test "$(ACCESS)" = mtls || { echo "  client certs are for ACCESS=mtls (config.mk has $(ACCESS))"; exit 1; }
> @test -n "$(NAME_ARG)" || { echo "usage: make cert-revoke NAME_ARG=<device>   (names: make client-cert-list)"; exit 1; }
> @test -f $(AUTHDIR)/$(NAME_ARG).crt || { echo "  no cert named $(NAME_ARG) (make client-cert-list)"; exit 1; }
> @# The .crt stays, so the name keeps pointing at its (now revoked) serial.
> @S=$$(openssl x509 -in $(AUTHDIR)/$(NAME_ARG).crt -noout -serial | cut -d= -f2) && \
   if grep -q "^$$S " $(AUTHDIR)/revoked.map 2>/dev/null; then echo "  $(NAME_ARG) was already revoked"; \
   else echo "$$S 1;  # $(NAME_ARG), revoked $$(date -u +%F)" >> $(AUTHDIR)/revoked.map && \
        nginx -t 2>/dev/null && systemctl reload nginx && echo "  revoked $(NAME_ARG) (serial $$S): nginx now answers it with 403"; fi

client-cert-list:  ## mtls: list issued client certs and which are revoked
> @for c in $(AUTHDIR)/*.crt; do n=$$(basename "$$c" .crt); [ "$$n" = ca ] || [ ! -e "$$c" ] && continue; \
   S=$$(openssl x509 -in "$$c" -noout -serial | cut -d= -f2); \
   if grep -q "^$$S " $(AUTHDIR)/revoked.map 2>/dev/null; then st=REVOKED; \
   else st="valid until $$(openssl x509 -in "$$c" -noout -enddate | cut -d= -f2)"; fi; \
   printf "  %-16s %s\n" "$$n" "$$st"; done

web-passwd:  ## mtls/public: set the web password:  make web-passwd USER_ARG=me
> @test "$(ACCESS)" != tailscale || { echo "  no web password in tailscale mode: your tailnet is the lock"; exit 1; }
> @test "$(ACCESS)" != ssh || { echo "  no web password in ssh mode: there is no web UI"; exit 1; }
> @test -n "$(USER_ARG)" || { echo "usage: make web-passwd USER_ARG=<user>"; exit 1; }
> @# Generated, never chosen. nginx rereads the file on every request.
> @mkdir -p $(AUTHDIR) && P=$$(openssl rand -base64 15 | tr -d '/+=' | head -c 18) && \
   printf "%s:%s\n" "$(USER_ARG)" "$$(openssl passwd -apr1 $$P)" > $(AUTHDIR)/htpasswd && \
   echo "  $(USER_ARG) / $$P"

## --- backups (runs on the host; see README) -----------------------------
backup-link:  ## Install the hourly backup: script, systemd units, timer
> @test -f /root/backup/b2.env || { echo "  no /root/backup/b2.env: run as root, after the kopia setup in the README"; exit 1; }
> ln -sfn $(CURDIR)/backup/agent-box-backup /usr/local/sbin/agent-box-backup
> systemctl link $(CURDIR)/backup/agent-box-backup.service $(CURDIR)/backup/agent-box-backup.timer
> systemctl daemon-reload
> systemctl enable --now agent-box-backup.timer
> @systemctl list-timers agent-box-backup.timer --no-pager | head -2 | sed 's/^/  /'

backup-status:  ## Is a backup running, when is the next, latest snapshots
> @# A running oneshot service is "activating", never "active".
> @if [ "$$(systemctl is-active agent-box-backup.service)" = activating ]; then echo "  backup: running now"; \
   else echo "  backup: idle, last result: $$(systemctl show -p Result --value agent-box-backup.service)"; fi
> @systemctl list-timers agent-box-backup.timer --no-pager | head -2 | sed 's/^/  /'
> @HOME=/root kopia snapshot list --all | tail -n 20

backup-now:  ## Start a backup now, in the background
> systemctl start --no-block agent-box-backup.service
> @echo "  started - follow it with: journalctl -fu agent-box-backup"

## --- network guard (container -> host / internal addresses) -------------
guard-link:  ## Install the nftables guard that keeps the container off the host
> ln -sfn $(CURDIR)/firewall/guard.sh /usr/local/sbin/agent-box-guard
> systemctl link $(CURDIR)/firewall/agent-box-guard.service
> systemctl daemon-reload && systemctl enable agent-box-guard && systemctl restart agent-box-guard

guard-off:  ## Lift the guard until the next boot or `make up` (isolated agents then refuse to start)
> systemctl stop agent-box-guard
> /usr/local/sbin/agent-box-guard off

net-test:  ## Show what the container can reach (run after any firewall change)
> @docker cp $(CURDIR)/firewall/net-probe.sh $(NAME):/tmp/net-probe.sh
> @P=$$(ip -4 route get 1.1.1.1 | grep -o 'src [0-9.]*' | cut -d' ' -f2); \
   echo "as dev:"; docker exec -u dev $(NAME) bash /tmp/net-probe.sh "$$P"; \
   C=$$(docker exec $(NAME) sh -c 'ls /cells/*/.cell 2>/dev/null | head -1 | cut -d/ -f3'); \
   if [ -n "$$C" ]; then echo "as the isolated agent $$C:"; docker exec $(NAME) sudo -u cell-$$C bash /tmp/net-probe.sh "$$P" cell; fi; \
   docker exec $(NAME) rm -f /tmp/net-probe.sh

## --- checks -------------------------------------------------------------
status: ps  ## Show container, web access and fail2ban status
> @echo "--- t3:";      docker exec $(NAME) su dev -s /bin/sh -c 'tmux ls' 2>&1 | sed 's/^/  /'
> @curl -sf -o /dev/null -w "  t3 direct:  %{http_code}\n" http://127.0.0.1:3773/ || true
> @echo "--- web (ACCESS=$(ACCESS)):"
> @$(MAKE) --no-print-directory status-$(ACCESS)
> @echo "--- fail2ban:"; fail2ban-client status sshd 2>/dev/null | grep -E "Currently banned|Total banned" | sed 's/^/  sshd /'

status-tailscale:
> @tailscale serve status 2>&1 | sed 's/^/  /'

status-ssh:
> @echo "  no web UI: T3 apps connect over SSH (agent-box)"

status-mtls status-public:
> @curl -sk -o /dev/null -w "  nginx:      %{http_code} (401 expected without credentials)\n" https://$(DOMAIN)/ || true
> @fail2ban-client status nginx-http-auth 2>/dev/null | grep -E "Currently banned|Total banned" | sed 's/^/  nginx-http-auth /' || true

ps:  ## Container process state
> @docker ps --filter name=$(NAME) --format "  {{.Names}} | {{.Status}} | {{.Ports}}"

doctor:  ## Verify the things that have broken before
> @echo "checking CLIs..."
> @docker exec -u dev -e HOME=/home/dev $(NAME) sh -c 'echo "  claude $$(claude --version)"; echo "  codex  $$(codex --version)"; echo "  t3     $$(t3 --version)"'
> @echo "checking T3's terminals (node-pty in its runtime)..."
> @docker exec -u dev $(NAME) sh -c 'v=$$(t3 --version | grep -o "[0-9]*\.[0-9.]*" | head -1); test -d /home/dev/.t3/runtime/versions/$$v/node_modules/node-pty' \
   && echo "  node-pty OK" || echo "  WARNING: no node-pty in T3's runtime - make t3-restart, then check make t3-logs"
> @echo "checking mounts..."
> @docker exec $(NAME) sh -c 'for d in /home/dev /data; do printf "  %-10s %s\n" $$d "$$(mountpoint -q $$d && echo mounted || echo NOT-MOUNTED)"; done'
> @echo "checking T3 is reachable through the port publish (not bound to 127.0.0.1)..."
> @docker exec -u dev $(NAME) ps -eo args | grep -q -- "t3 serve.*--host 0.0.0.0" && echo "  t3 bound to 0.0.0.0 OK" || echo "  WARNING: t3 not on 0.0.0.0 (did its tmux die?) - the web UI will 502, and a server the T3 app started has no ~/.env or cell guards: make t3-restart"
> @echo "checking host key persistence..."
> @ls $(CURDIR)/ssh_host_keys/ssh_host_ed25519_key >/dev/null 2>&1 && echo "  host keys persisted OK" || echo "  WARNING: host keys not persisted"
> @echo "checking network guard..."
> @B=br-$$(docker network inspect -f '{{.Id}}' $(NAME)_default | cut -c1-12); nft list table inet agent_box_guard 2>/dev/null | grep -q "\"$$B\"" && echo "  guard active on $$B" || echo "  WARNING: guard missing or aimed at an old bridge (sudo make guard-link)"
> @P=$$(docker inspect -f '{{.State.Pid}}' $(NAME)); nsenter -t $$P -n nft list table inet agent_box_cells >/dev/null 2>&1 \
   && echo "  isolated agents' table active" || echo "  WARNING: isolated agents' table missing (sudo systemctl restart agent-box-guard; or this needs root)"
> @echo "checking web access (ACCESS=$(ACCESS))..."
> @$(MAKE) --no-print-directory doctor-$(ACCESS)

doctor-tailscale:
> @tailscale status >/dev/null 2>&1 && echo "  tailscale up OK" || echo "  WARNING: tailscale is not up - sudo tailscale up"
> @S=$$(tailscale serve status 2>&1); \
   echo "$$S" | grep -q '127.0.0.1:3773' && echo "  tailscale serve -> 127.0.0.1:3773 OK (https://$(DOMAIN))" \
     || echo "  WARNING: tailscale is not serving T3 (or this needs root) - sudo make host-config"; \
   echo "$$S" | grep -qi 'funnel on' && echo "  WARNING: Funnel is on, so T3 is open to the whole internet - sudo tailscale serve reset && sudo make host-config"; \
   true
> @ls /etc/nginx/sites-enabled/agent-box*.conf >/dev/null 2>&1 && echo "  WARNING: an agent-box nginx site is still enabled - sudo make host-config" || echo "  no agent-box nginx site OK"

doctor-ssh:
> @ls /etc/nginx/sites-enabled/agent-box*.conf >/dev/null 2>&1 && echo "  WARNING: an agent-box nginx site is still enabled - sudo make host-config" || echo "  no agent-box nginx site OK"
> @command -v tailscale >/dev/null && tailscale serve status 2>&1 | grep -q '127.0.0.1:3773' \
   && echo "  WARNING: tailscale is still serving T3 - sudo make host-config" || echo "  no tailscale serve for T3 OK"
> @docker exec $(NAME) /usr/sbin/sshd -T -f /etc/ssh/sshd_config_box 2>/dev/null | grep -qx 'allowtcpforwarding yes' \
   && echo "  box sshd allows port forwarding (the T3 app needs it) OK" || echo "  WARNING: the box's sshd refuses port forwarding (or this needs root): the T3 app can't connect"

doctor-mtls doctor-public: doctor-%:
> @test -e /etc/nginx/sites-enabled/agent-box-$*.conf && echo "  nginx site agent-box-$*.conf linked OK" || echo "  WARNING: nginx site not linked - sudo make host-config"
> @grep -q "server_name $(DOMAIN);" nginx/agent-box-$*.conf && echo "  server_name $(DOMAIN) OK" || echo "  WARNING: nginx/agent-box-$*.conf does not say $(DOMAIN) (config.mk)"
> @test $* != mtls || { test -f $(AUTHDIR)/ca.crt && echo "  client CA OK" || echo "  WARNING: no client CA - sudo make ca"; }
> @test -f $(AUTHDIR)/htpasswd && echo "  web password set" || \
   { test $* = public && echo "  WARNING: no web password - sudo make web-passwd USER_ARG=me" || echo "  no password fallback: cert only"; }
> @code=$$(curl -sk -o /dev/null -w '%{http_code}' https://$(DOMAIN)/); case $$code in \
     2*|3*) echo "  WARNING: https://$(DOMAIN) answered $$code without credentials - it is OPEN" ;; \
     000)   echo "  WARNING: https://$(DOMAIN) is not reachable from here" ;; \
     *)     echo "  https://$(DOMAIN) refuses requests without credentials ($$code) OK" ;; esac
> @fail2ban-client status nginx-http-auth >/dev/null 2>&1 && echo "  fail2ban nginx-http-auth jail OK" || echo "  WARNING: fail2ban nginx-http-auth jail not running (or not root)"
