# agent-box: every zsh in the box sources this (from /etc/zsh/zshrc).

# The same PATH T3 gives the agents: /opt/agent-box/bin first (cell, desktop,
# claude-account, and the claude/codex guards for isolated agents), then your
# own bin folders.
typeset -U path
path=(/opt/agent-box/bin $HOME/.local/bin $HOME/bin $path)

# A reminder when you walk into an isolated agent's folder.
_agent_box_cell_hint() {
  case $PWD/ in /cells/*/*) local n=${PWD#/cells/}; n=${n%%/*}
    [[ ${_agent_box_cell-} == $n ]] || print -P "%F{yellow}This folder belongs to the isolated agent $n. You are still dev here, so do not run its scripts; cell $n gives you its shell.%f"
    _agent_box_cell=$n ;;
  *) _agent_box_cell= ;; esac
}
autoload -Uz add-zsh-hook && add-zsh-hook chpwd _agent_box_cell_hint && _agent_box_cell_hint

# claude-<name> for each extra Claude login (claude-account add <name>).
for _d in $HOME/.claude-*(N/); do
  [[ ${_d:t} =~ '^\.claude-[a-z][a-z0-9]*$' ]] && alias "claude-${_d:t:s/.claude-//}=CLAUDE_CONFIG_DIR=${(q)_d} claude"
done
unset _d
