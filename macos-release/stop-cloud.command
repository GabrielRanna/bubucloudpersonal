#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
. "$SCRIPT_DIR/common.sh"

stop_pid_file "$CLOUDFLARED_PID_FILE"
stop_pid_file "$GATEWAY_PID_FILE"
stop_pid_file "$FILEBROWSER_PID_FILE"

stop_process_by_hint "cloudflared" "127.0.0.1:${PUBLIC_PORT}"
stop_process_by_hint "$(basename "${PYTHON_EXE:-python3}")" "$GATEWAY_SCRIPT"
stop_process_by_hint "filebrowser" "$FILEBROWSER_DB"

write_connection_info ""
log "Nuvem pessoal parada."
