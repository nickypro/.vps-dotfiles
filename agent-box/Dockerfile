# Agent box: Claude Code + Codex + T3 Code in one container, reachable over SSH.
FROM node:24-bookworm

ARG TZ=Etc/UTC
ENV TZ=${TZ} DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server ca-certificates curl wget git \
      build-essential python3 python3-venv python3-pip pipx \
      tmux ripgrep jq less vim nano unzip zip procps htop rsync \
      zsh fzf locales sudo acl \
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
# root joins group dev: isolated agents get processes hidden (hidepid, with
# group dev exempt), and `docker exec -u root` must still see everything.
RUN groupmod -n dev node \
 && usermod -l dev -d /home/dev -s /usr/bin/zsh node \
 && usermod -aG dev root \
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

# The three agent CLIs. --allow-scripts: npm 11 skips install scripts unless
# told, and Claude Code's sets up its native binary. T3 (0.1 and later) is
# only a launcher here: it fetches its real, self-contained binary into
# ~/.t3/runtime on first start, so that part lives on the home volume.
# `make build` passes today's date as AGENTS_STAMP, so a rebuild fetches the
# latest CLIs instead of reusing a cached layer from months ago (which would
# also quietly undo any `make update` done since).
ARG AGENTS_STAMP=0
RUN npm install -g --allow-scripts=@anthropic-ai/claude-code,msgpackr-extract,node-pty \
      @anthropic-ai/claude-code @openai/codex t3 \
 && npm cache clean --force \
 && claude --version && codex --version

# Optional extras (EXTRAS in config.mk; `make build` passes them on):
#   desktop   a private remote desktop you open in your browser (noVNC, with
#             live sound), plus Chromium on it for agents to drive
#   wine      what Windows apps need under Wine, e.g. Synthesizer V
#             (extras/synthv; needs desktop too)
#   scraping  Python scraping tools in /opt/scrape (see the README)
ARG EXTRAS=""
RUN set -e; has() { case " $EXTRAS " in *" $1 "*) return 0;; esac; return 1; }; \
    pkgs=""; \
    if has desktop; then pkgs="$pkgs tigervnc-standalone-server tigervnc-common novnc websockify \
        pulseaudio pulseaudio-utils openbox xterm xdotool x11-utils x11-xserver-utils xauth \
        imagemagick xdg-utils socat xvfb chromium fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji \
        fonts-liberation fonts-dejavu-core"; fi; \
    if has wine; then pkgs="$pkgs cabextract desktop-file-utils libgl1-mesa-dri libglx-mesa0 \
        libegl-mesa0 mesa-vulkan-drivers libvulkan1 libfreetype6 libfontconfig1 libgnutls30 \
        libpulse0 libxrandr2 libxinerama1 libxcursor1 libxi6 libxcomposite1 libxext6 libxrender1 \
        libsm6 libice6 libxkbcommon0 libxfixes3 libxxf86vm1 libunwind8"; fi; \
    if has scraping; then pkgs="$pkgs ffmpeg"; fi; \
    if [ -n "$pkgs" ]; then apt-get update && apt-get install -y --no-install-recommends $pkgs \
        && rm -rf /var/lib/apt/lists/*; fi; \
    if has scraping; then \
      curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
      && uv venv /opt/scrape --python 3.11 \
      && uv pip install --python /opt/scrape/bin/python --no-cache \
           curl_cffi trafilatura "yt-dlp[default,curl-cffi]" "camoufox[geoip]" playwright \
           beautifulsoup4 lxml httpx markitdown \
      && for b in trafilatura yt-dlp markitdown camoufox playwright; do ln -sf /opt/scrape/bin/$b /usr/local/bin/$b; done; \
    fi

# Isolated agents ("cells") and the pieces that keep them isolated. See
# cells/cell-admin. The git shim goes ahead of /usr/bin/git for everyone;
# /opt/agent-box/bin (claude/codex guards, `cell`, t3-serve) is first on
# PATH for T3 and for your interactive shells.
COPY cells/ /opt/agent-box/cells/
COPY bin/ /opt/agent-box/bin/
COPY extras/ /opt/agent-box/extras/
RUN chmod 755 /opt/agent-box/cells/* /opt/agent-box/bin/* \
 && chmod 644 /opt/agent-box/cells/lib.sh \
 && ln -sf ../cells/agent-guard /opt/agent-box/bin/claude \
 && ln -sf ../cells/agent-guard /opt/agent-box/bin/codex \
 && ln -sf ../cells/cell /opt/agent-box/bin/cell \
 && ln -sf /opt/agent-box/cells/git /usr/local/bin/git \
 && ln -sf /opt/agent-box/extras/desktop/desktop /opt/agent-box/bin/desktop \
 && ln -sf /opt/agent-box/extras/synthv/synthv /opt/agent-box/bin/synthv \
 && printf '%s\n' '' \
      '# agent-box: /opt/agent-box/bin first (cell, desktop, and the claude/codex' \
      '# guards for isolated agents), and a reminder inside an agent'"'"'s folder.' \
      'case ":$PATH:" in *:/opt/agent-box/bin:*) ;; *) PATH=/opt/agent-box/bin:$PATH ;; esac' \
      '_agent_box_cell_hint() {' \
      '  case $PWD/ in /cells/*/*) local n=${PWD#/cells/}; n=${n%%/*}' \
      '    [[ ${_agent_box_cell-} == $n ]] || print -P "%F{yellow}This folder belongs to the isolated agent $n. You are still dev here, so do not run its scripts; cell $n gives you its shell.%f"' \
      '    _agent_box_cell=$n ;;' \
      '  *) _agent_box_cell= ;; esac' \
      '}' \
      'autoload -Uz add-zsh-hook && add-zsh-hook chpwd _agent_box_cell_hint && _agent_box_cell_hint' \
      >> /etc/zsh/zshrc

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
