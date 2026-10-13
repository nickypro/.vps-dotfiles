# Agent box. Everything here is declarative: the container, the nginx site,
# the fail2ban jails and the backup units all live in this directory and are
# symlinked into place, so `git diff` shows the full state of the deployment.
#
# Settings (how the web UI is reached, your domain) are in config.mk.
#
# Uses .RECIPEPREFIX so recipes are indented with ">" instead of tabs.
.RECIPEPREFIX = >
.DEFAULT_GOAL := help
SHELL := /bin/bash

-include config.mk
ACCESS ?= tailscale
ifeq ($(filter $(ACCESS),tailscale mtls public),)
  $(error ACCESS must be one of: tailscale mtls public - see config.mk)
endif

COMPOSE := docker compose
NAME    := agent-box
AUTHDIR := /etc/nginx/agent-box

# The web UI's hostname. Tailscale mode looks up this machine's MagicDNS name
# (myvps.your-tailnet.ts.net); the nginx modes take it from config.mk.
ifeq ($(ACCESS),tailscale)
  DOMAIN ?= $(shell tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' 2>/dev/null | sed 's/\.$$//')
endif
DOMAIN ?= code.example.com

.PHONY: help build up down restart rebuild logs shell t3-logs t3-restart pair \
        host-config host-config-tailscale host-config-mtls host-config-public fail2ban-config \
        ca cert client-cert-list web-passwd \
        backup-link backup-status backup-now \
        status status-tailscale status-mtls status-public ps \
        doctor doctor-tailscale doctor-mtls doctor-public

help:  ## Show this help
> @grep -hE '^[a-z0-9-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}'
> @echo "  ACCESS=$(ACCESS) (config.mk)"

## --- container ----------------------------------------------------------
build:  ## Build the image
> $(COMPOSE) build

up:  ## Start (or recreate) the container
> @test -f authorized_keys || { echo "create ./authorized_keys first (see authorized_keys.example)"; exit 1; }
> mkdir -p ssh_host_keys
> $(COMPOSE) up -d

down:  ## Stop and remove the container (volume data is untouched)
> $(COMPOSE) down

restart:  ## Restart the container
> $(COMPOSE) restart

rebuild: build up  ## Rebuild the image and recreate the container

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
> -docker exec $(NAME) pkill -u dev -f "t3 serve"
> docker exec -d $(NAME) su dev -s /bin/sh -c 'tmux new-session -d -s t3 "t3 serve --mode web --host 0.0.0.0 --port 3773 --no-browser --auto-bootstrap-project-from-cwd /home/dev 2>&1 | tee -a /home/dev/.t3-serve.log"'
> @sleep 3 && curl -sf -o /dev/null -w "  t3 http: %{http_code}\n" http://127.0.0.1:3773/ || echo "  t3 not responding yet"

pair:  ## Mint a T3 pairing token for the web UI (30 min)
> @test -n "$(DOMAIN)" || { echo "  no DOMAIN: is tailscale up and jq installed? Or set DOMAIN in config.mk"; exit 1; }
> @docker exec $(NAME) su dev -s /bin/sh -c 't3 auth pairing create --ttl 30m --label laptop --base-url https://$(DOMAIN)' | grep -aE 'Token:|Pair URL:|Expires' || true

## --- web access: host side (ACCESS in config.mk) ------------------------
host-config: host-config-$(ACCESS) fail2ban-config  ## Set up web access for ACCESS, plus fail2ban

# Each mode removes the other modes' pieces (after its own checks pass), so
# switching is just "edit config.mk, run sudo make host-config again".
UNLINK_NGINX := rm -f /etc/nginx/sites-enabled/agent-box*.conf /etc/fail2ban/jail.d/agent-box-nginx.local

host-config-tailscale:
> @tailscale status >/dev/null 2>&1 || { echo "  tailscale is not up: sudo tailscale up"; exit 1; }
> @# --bg keeps serving across reboots and tailscaled restarts. The first time,
> @# it may print a link to turn on HTTPS certificates for your tailnet.
> tailscale serve --bg --https=443 http://127.0.0.1:3773
> @# No nginx in this mode: drop any agent-box site an nginx mode left behind.
> $(UNLINK_NGINX)
> @if systemctl is-active -q nginx; then nginx -t && systemctl reload nginx; fi
> @echo "  web UI: https://$(DOMAIN)  (your tailnet only)"

host-config-mtls host-config-public: host-config-%:
> @test "$(DOMAIN)" != code.example.com || { echo "  set DOMAIN in config.mk first"; exit 1; }
> @grep -q "server_name $(DOMAIN);" nginx/agent-box-$*.conf || { echo "  put $(DOMAIN) in nginx/agent-box-$*.conf first (server_name and cert paths)"; exit 1; }
> @test -f /etc/letsencrypt/live/$(DOMAIN)/fullchain.pem || { echo "  no TLS cert yet: sudo certbot certonly --nginx -d $(DOMAIN)"; exit 1; }
> @test $* != mtls   || test -f $(AUTHDIR)/ca.crt   || { echo "  no client CA yet: sudo make ca"; exit 1; }
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
> @echo "  CA written to $(AUTHDIR) - keep exactly one copy of ca.key"

cert:  ## mtls: issue a client cert for a device:  make cert NAME_ARG=firefox
> @test "$(ACCESS)" = mtls || { echo "  client certs are for ACCESS=mtls (config.mk has $(ACCESS))"; exit 1; }
> @test -n "$(NAME_ARG)" || { echo "usage: make cert NAME_ARG=<device>"; exit 1; }
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

client-cert-list:  ## mtls: list issued client certs
> @ls -1 $(AUTHDIR)/*.crt 2>/dev/null | grep -v ca.crt | sed 's|.*/|  |;s|\.crt$$||' || echo "  none"

web-passwd:  ## mtls/public: set the web password:  make web-passwd USER_ARG=me
> @test "$(ACCESS)" != tailscale || { echo "  no web password in tailscale mode: your tailnet is the lock"; exit 1; }
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

## --- checks -------------------------------------------------------------
status: ps  ## Show container, web access and fail2ban status
> @echo "--- t3:";      docker exec $(NAME) su dev -s /bin/sh -c 'tmux ls' 2>&1 | sed 's/^/  /'
> @curl -sf -o /dev/null -w "  t3 direct:  %{http_code}\n" http://127.0.0.1:3773/ || true
> @echo "--- web (ACCESS=$(ACCESS)):"
> @$(MAKE) --no-print-directory status-$(ACCESS)
> @echo "--- fail2ban:"; fail2ban-client status sshd 2>/dev/null | grep -E "Currently banned|Total banned" | sed 's/^/  sshd /'

status-tailscale:
> @tailscale serve status 2>&1 | sed 's/^/  /'

status-mtls status-public:
> @curl -sk -o /dev/null -w "  nginx:      %{http_code} (401 expected without credentials)\n" https://$(DOMAIN)/ || true
> @fail2ban-client status nginx-http-auth 2>/dev/null | grep -E "Currently banned|Total banned" | sed 's/^/  nginx-http-auth /' || true

ps:  ## Container process state
> @docker ps --filter name=$(NAME) --format "  {{.Names}} | {{.Status}} | {{.Ports}}"

doctor:  ## Verify the things that have broken before
> @echo "checking node-pty native build..."
> @docker exec $(NAME) node -e "require('/usr/local/lib/node_modules/t3/node_modules/node-pty');console.log('  node-pty OK')"
> @echo "checking CLIs..."
> @docker exec $(NAME) sh -lc 'echo "  claude $$(claude --version)"; echo "  codex  $$(codex --version)"; echo "  t3     $$(t3 --version)"'
> @echo "checking mounts..."
> @docker exec $(NAME) sh -c 'for d in /home/dev /data; do printf "  %-10s %s\n" $$d "$$(mountpoint -q $$d && echo mounted || echo NOT-MOUNTED)"; done'
> @echo "checking T3 is reachable through the port publish (not bound to 127.0.0.1)..."
> @docker exec $(NAME) ps -eo args | grep -q -- "t3 serve.*--host 0.0.0.0" && echo "  t3 bound to 0.0.0.0 OK" || echo "  WARNING: t3 not on 0.0.0.0 - the web UI will 502"
> @echo "checking host key persistence..."
> @ls $(CURDIR)/ssh_host_keys/ssh_host_ed25519_key >/dev/null 2>&1 && echo "  host keys persisted OK" || echo "  WARNING: host keys not persisted"
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
