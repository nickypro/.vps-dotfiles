# Seeded once into /home/dev on first start. This file lives on the host
# volume, so edits persist and are never overwritten by a rebuild.

export LANG='en_US.UTF-8'
export LANGUAGE='en_US:en'
export LC_ALL='en_US.UTF-8'

# oh-my-zsh lives in /opt (read-only, baked into the image) because /home/dev
# is a bind mount. Cache and completion dumps go to the volume instead.
export ZSH="/opt/oh-my-zsh"
export ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
mkdir -p "$ZSH_CACHE_DIR/completions"
zstyle ':omz:update' mode disabled   # /opt is root-owned; update via rebuild

ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git fzf zsh-autosuggestions zsh-syntax-highlighting)  # highlighting last

source $ZSH/oh-my-zsh.sh

POWERLEVEL9K_SHORTEN_STRATEGY="truncate_to_last"
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(user dir vcs status)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=()
POWERLEVEL9K_STATUS_OK=false
POWERLEVEL9K_STATUS_CROSS=true

[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ]   && source /usr/share/doc/fzf/examples/completion.zsh

# History on the volume, so it survives container rebuilds.
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=100000
export SAVEHIST=100000
setopt SHARE_HISTORY INC_APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

alias tmux='tmux -u'
alias ll='ls -alh'

# Secrets: keep them in a 0600 file rather than in this file, which ends up in
# backups and screenshares. dotenv format (KEY=value, no `export`), so `set -a`
# is what actually exports them -- sourcing it without that leaves them as
# plain shell locals that child processes never see.
if [ -r "$HOME/.env" ]; then set -a; . "$HOME/.env"; set +a; fi

autoload -Uz compinit && compinit -d "$ZSH_CACHE_DIR/zcompdump"

[ -f "$HOME/.p10k.zsh" ] && source "$HOME/.p10k.zsh"

# --- claude: Remote Control on by default -------------------------------
# `claude --remote-control` registers the session with claude.ai/code so it can
# also be driven from the web. There is no settings key or env var for this,
# so a shell function is the only way to make it the default.
#
# Deliberately a FUNCTION, not a wrapper script on PATH: T3 spawns the claude
# binary itself in non-interactive stream-json mode, and --remote-control means
# "start an INTERACTIVE session", so forcing it there would break T3. A shell
# function is only seen by your own terminal.
#
# Escape hatch: CLAUDE_NO_RC=1 claude ...
claude() {
  local bin; bin=$(whence -p claude) || { echo "claude not found on PATH" >&2; return 127; }

  # Any subcommand, any non-interactive mode, an explicit flag, or a
  # non-terminal stdin means we pass through untouched.
  local passthrough=0
  [[ -n "${CLAUDE_NO_RC:-}" ]] && passthrough=1
  [[ -t 0 ]] || passthrough=1
  local a
  for a in "$@"; do
    case "$a" in
      agents|attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|\
      plugin|plugins|project|respawn|rm|update|config|setup-token|migrate-installer)
        passthrough=1 ;;
      -p|--print|--output-format|--input-format|--remote-control|-h|--help|-v|--version)
        passthrough=1 ;;
    esac
  done

  if (( passthrough )); then
    "$bin" "$@"
  else
    "$bin" --remote-control "$@"
  fi
}
