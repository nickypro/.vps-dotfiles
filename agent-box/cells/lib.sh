# shellcheck shell=bash
# Shared by the cell scripts. A cell is an isolated agent: Linux user
# cell-<name>, everything under /cells/<name>, a uid from 2001-2999 (the
# network guard matches that range, so keep the two in step).
CELLS=/cells
CELL_UID_MIN=2001
CELL_UID_MAX=2999

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
