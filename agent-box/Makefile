# Agent box. Everything here is declarative: the container, the nginx site and
# the fail2ban jail all live in this directory and are symlinked into place,
# so `git diff` shows the full state of the deployment.
#
# Uses .RECIPEPREFIX so recipes are indented with ">" instead of tabs.
.RECIPEPREFIX = >
.DEFAULT_GOAL := help
SHELL := /bin/bash

COMPOSE := docker compose
NAME    := agent-box
CERTDIR := /etc/nginx/mtls
DOMAIN  ?= code.example.com

.PHONY: help build up down restart rebuild logs shell t3-logs t3-restart pair host-config ca cert client-cert-list web-passwd status ps doctor

help:  ## Show this help
> @grep -hE '^[a-z0-9-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}'

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
> @docker exec $(NAME) su dev -s /bin/sh -c 't3 auth pairing create --ttl 30m --label laptop --base-url https://$(DOMAIN)' | grep -aE 'Token:|Pair URL:|Expires' || true

## --- host configuration -------------------------------------------------
host-config:  ## Link nginx + fail2ban config from this repo and reload
> ln -sfn $(CURDIR)/nginx/agent-box.conf /etc/nginx/sites-enabled/agent-box.conf
> ln -sfn $(CURDIR)/fail2ban/jail.local /etc/fail2ban/jail.local
> nginx -t && systemctl reload nginx
> fail2ban-client -t && systemctl restart fail2ban
> @echo "  host config applied"

## --- access -------------------------------------------------------------
ca:  ## Create the private CA for client certs (once)
> @test ! -e $(CERTDIR)/ca.key || { echo "CA already exists in $(CERTDIR)"; exit 1; }
> mkdir -p $(CERTDIR) && cd $(CERTDIR) && umask 077 && \
   openssl req -x509 -newkey rsa:4096 -nodes -keyout ca.key -out ca.crt \
     -days 3650 -subj "/CN=agent-box client CA" 2>/dev/null && chmod 644 ca.crt
> @echo "  CA written to $(CERTDIR) - keep exactly one copy of ca.key"

cert:  ## Issue a client cert for a device:  make cert NAME_ARG=firefox
> @test -n "$(NAME_ARG)" || { echo "usage: make cert NAME_ARG=<device>"; exit 1; }
> @cd $(CERTDIR) && umask 077 && \
   PASS=$$(openssl rand -base64 18 | tr -d '/+=' | head -c 20) && \
   openssl genrsa -out $(NAME_ARG).key 2048 2>/dev/null && \
   openssl req -new -key $(NAME_ARG).key -subj "/CN=$(NAME_ARG)" -out $(NAME_ARG).csr 2>/dev/null && \
   openssl x509 -req -in $(NAME_ARG).csr -CA ca.crt -CAkey ca.key -CAcreateserial \
     -out $(NAME_ARG).crt -days 825 -sha256 2>/dev/null && \
   openssl pkcs12 -export -out $(NAME_ARG).p12 -inkey $(NAME_ARG).key -in $(NAME_ARG).crt \
     -certfile ca.crt -name "agent-box ($(NAME_ARG))" -passout pass:$$PASS 2>/dev/null && \
   rm -f $(NAME_ARG).csr && \
   echo "  wrote $(CERTDIR)/$(NAME_ARG).p12   password: $$PASS" && \
   echo "  copy it off, then: rm $(CERTDIR)/$(NAME_ARG).p12 $(CERTDIR)/$(NAME_ARG).key"

client-cert-list:  ## List issued client certs
> @ls -1 $(CERTDIR)/*.crt 2>/dev/null | grep -v ca.crt | sed 's|.*/|  |;s|\.crt$$||' || echo "  none"

web-passwd:  ## Set the web password fallback:  make web-passwd USER_ARG=me
> @test -n "$(USER_ARG)" || { echo "usage: make web-passwd USER_ARG=<user>"; exit 1; }
> @mkdir -p $(CERTDIR) && P=$$(openssl rand -base64 15 | tr -d '/+=' | head -c 18) && \
   printf "%s:%s\n" "$(USER_ARG)" "$$(openssl passwd -apr1 $$P)" > $(CERTDIR)/htpasswd && \
   systemctl reload nginx && echo "  $(USER_ARG) / $$P"

## --- checks -------------------------------------------------------------
status: ps  ## Show container + service status
> @echo "--- t3:";      docker exec $(NAME) su dev -s /bin/sh -c 'tmux ls' 2>&1 | sed 's/^/  /'
> @curl -sf -o /dev/null -w "  t3 direct:  %{http_code}\n" http://127.0.0.1:3773/ || true
> @curl -sk -o /dev/null -w "  nginx:      %{http_code} (401 expected without a cert)\n" https://$(DOMAIN)/ || true
> @echo "--- fail2ban:"; fail2ban-client status sshd 2>/dev/null | grep -E "Currently banned|Total banned" | sed 's/^/  /'

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
> @docker exec $(NAME) ps -eo args | grep -q -- "t3 serve.*--host 0.0.0.0" && echo "  t3 bound to 0.0.0.0 OK" || echo "  WARNING: t3 not on 0.0.0.0 - nginx will 502"
> @echo "checking host key persistence..."
> @ls $(CURDIR)/ssh_host_keys/ssh_host_ed25519_key >/dev/null 2>&1 && echo "  host keys persisted OK" || echo "  WARNING: host keys not persisted"
