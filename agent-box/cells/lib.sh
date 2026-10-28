# shellcheck shell=bash
# Shared by the cell scripts. A cell is an isolated agent: Linux user
# cell-<name> (also in group "cells"), everything under /cells/<name>, a uid
# from 2001-2999 (the network guard matches that range, so keep the two in
# step).
CELLS=/cells
CELL_UID_MIN=2001
CELL_UID_MAX=2999
CELLS_GID=2000

# Per-box settings, optional (/opt/agent-box/cells.conf, from the image):
#   CELL_PRIVATE_DIRS  your folders: "other" permissions get taken off them,
#                      since a cell can read anything world-readable
#   CELL_DENY_DIRS     shared scratch folders cells may write to but not list.
#                      /tmp is the big one: your agents leave world-readable
#                      files there. Cells get their own TMPDIR, but tools that
#                      insist on /tmp (an X server's lock file, say) still work.
CELL_PRIVATE_DIRS="/home/dev /data"
CELL_DENY_DIRS="/tmp /var/tmp"
if [ -r /opt/agent-box/cells.conf ]; then . /opt/agent-box/cells.conf; fi

cell_name_ok() { [[ ${1-} =~ ^[a-z][a-z0-9]{0,19}$ ]]; }

cell_exists() { cell_name_ok "${1-}" && [[ -f $CELLS/$1/.cell ]]; }

cell_uid() { sed -n 's/^uid=\([0-9]*\)$/\1/p' "$CELLS/$1/.cell"; }

# The cell a path belongs to, after resolving symlinks and "..", or nothing.
# Relative paths are taken from $2 (default: the current folder).
cell_of() {
  local p=$1 n
  [[ $p == /* ]] || p=${2:-$PWD}/$p
  p=$(realpath -m -- "$p" 2>/dev/null) || return 0
  [[ $p == "$CELLS"/* ]] || return 0
  n=${p#"$CELLS"/}; n=${n%%/*}
  if cell_exists "$n"; then printf '%s\n' "$n"; fi
  return 0
}
