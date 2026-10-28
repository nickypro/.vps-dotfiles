# Agent box: Claude Code + Codex + T3 Code in one container, reachable over SSH.
FROM node:24-bookworm

ARG TZ=Etc/UTC
ENV TZ=${TZ} DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server ca-certificates curl wget git \
      build-essential python3 python3-venv python3-pip pipx \
      tmux ripgrep jq less vim nano unzip zip procps htop rsync \
      zsh fzf locales sudo \
 && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI, from GitHub's own apt repo (Debian's is years behind). Auth lives
# in ~/.config/gh on the home volume, so a rebuild keeps the login.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# The node image already owns uid/gid 1000 as "node". Rename rather than
# renumber, so files land as uid 1000 == the host user that owns the data
# volume. Home is a bind mount, so -d without -m.
RUN groupmod -n dev node \
 && usermod -l dev -d /home/dev -s /usr/bin/zsh node \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
 && chmod 440 /etc/sudoers.d/dev

# oh-my-zsh + powerlevel10k live in /opt, NOT /home/dev: the home directory is
# a bind mount at runtime, so anything installed there in the image would be
# hidden. Only the small dotfiles get seeded into the volume by the entrypoint.
ENV ZSH=/opt/oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc \
 && git clone --depth=1 https://github.com/romkatv/powerlevel10k          ${ZSH}/custom/themes/powerlevel10k \
 && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions  ${ZSH}/custom/plugins/zsh-autosuggestions \
 && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH}/custom/plugins/zsh-syntax-highlighting \
 && rm -rf ${ZSH}/.git ${ZSH}/custom/themes/powerlevel10k/.git \
           ${ZSH}/custom/plugins/zsh-autosuggestions/.git \
           ${ZSH}/custom/plugins/zsh-syntax-highlighting/.git

COPY skel.zshrc /etc/skel-zsh/.zshrc

# The three agent CLIs. --allow-scripts is required or npm 11 silently skips
# node-pty's native build, which T3 needs for terminals.
# `make build` passes today's date as AGENTS_STAMP, so a rebuild fetches the
# latest CLIs instead of reusing a cached layer from months ago (which would
# also quietly undo any `make update` done since).
ARG AGENTS_STAMP=0
RUN npm install -g --allow-scripts=msgpackr-extract,node-pty \
      @anthropic-ai/claude-code @openai/codex t3 \
 && npm cache clean --force \
 && node -e "require('/usr/local/lib/node_modules/t3/node_modules/node-pty')" \
 && echo "node-pty native build OK"

# sshd. Keys come ONLY from a host-managed file mounted read-only at
# /etc/ssh/authorized_keys.d/dev, so access is rotated without touching the
# volume or rebuilding. ~/.ssh/authorized_keys is deliberately not read: an
# agent could write its own key there, and deleting a key from the host file
# would no longer be the whole story.
# No agent forwarding: anything with sudo in here (every agent) could use a
# forwarded agent socket to log in as you wherever your keys work.
# UsePAM yes is REQUIRED: the dev account has no password (locked, "!" in
# shadow) and OpenSSH rejects locked accounts as "invalid user" when PAM is off.
RUN mkdir -p /etc/ssh/authorized_keys.d /run/sshd \
 && printf '%s\n' \
      'Port 2222' \
      'HostKey /etc/ssh/host_keys/ssh_host_ed25519_key' \
      'HostKey /etc/ssh/host_keys/ssh_host_rsa_key' \
      'AddressFamily inet' \
      'PubkeyAuthentication yes' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'UsePAM yes' \
      'PermitRootLogin no' \
      'AllowUsers dev' \
      'AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u' \
      'AllowAgentForwarding no' \
      'X11Forwarding no' \
      'PrintMotd no' \
      'AcceptEnv LANG LC_*' \
      'ClientAliveInterval 60' \
      'Subsystem sftp /usr/lib/openssh/sftp-server' \
      > /etc/ssh/sshd_config_box \
 && sed -i 's/^session\s*required\s*pam_loginuid.so/#&/' /etc/pam.d/sshd

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV NODE_OPTIONS=--max-old-space-size=3072
WORKDIR /home/dev
EXPOSE 2222 3773
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
