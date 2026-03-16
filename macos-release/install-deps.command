#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
. "$SCRIPT_DIR/common.sh"

install_dependencies

log "Dependencias prontas para macOS."
log "File Browser: $FILEBROWSER_EXE"
log "cloudflared: $CLOUDFLARED_EXE"
