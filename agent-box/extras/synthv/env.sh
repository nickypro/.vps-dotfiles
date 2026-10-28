# shellcheck shell=bash
# Shared by setup and synthv: where Synthesizer V lives, and the desktop to show it on.
SV=${SV:-$HOME/.local/share/synthv}
export USER=${USER:-$(id -un)}
eval "$(/opt/agent-box/extras/desktop/desktop env)"
export WINEPREFIX=$SV/prefix WINEARCH=win64 WINEDEBUG=${WINEDEBUG:--all}
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=;mshtml="
SVR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
case ":$PATH:" in             # bin/xdg-open fixes the log-in hand-off; Wine after it
  *":$SVR/bin:$SV/wine/bin:"*) ;;
  *) export PATH=$SVR/bin:$SV/wine/bin:/opt/agent-box/bin:$PATH ;;
esac
export BROWSER=$SVR/browser   # Wine opens web links (the log-in page) with this
SYNTHV_EXE='C:\Program Files\Synthesizer V Studio 2 Pro\synthv-studio.exe'
