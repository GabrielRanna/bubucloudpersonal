#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
. "$SCRIPT_DIR/common.sh"

gateway_online="false"
filebrowser_online="false"
public_url="$(quick_tunnel_url 2>/dev/null || true)"

if curl -s --fail "http://127.0.0.1:${PUBLIC_PORT}" >/dev/null 2>&1; then
  gateway_online="true"
fi

if curl -s --fail "http://127.0.0.1:${FILEBROWSER_PORT}" >/dev/null 2>&1; then
  filebrowser_online="true"
fi

write_connection_info "$public_url"

echo "GatewayOnline     : $gateway_online"
echo "FileBrowserOnline : $filebrowser_online"
echo "GatewayPid        : $(read_pid "$GATEWAY_PID_FILE" 2>/dev/null || echo '')"
echo "FileBrowserPid    : $(read_pid "$FILEBROWSER_PID_FILE" 2>/dev/null || echo '')"
echo "CloudflaredPid    : $(read_pid "$CLOUDFLARED_PID_FILE" 2>/dev/null || echo '')"
echo "LocalUrl          : http://127.0.0.1:${PUBLIC_PORT}"
echo "PublicUrl         : ${public_url:-indisponivel}"
if [[ -n "$public_url" ]]; then
  echo "UploadUrl         : ${public_url}/upload-progress"
else
  echo "UploadUrl         : http://127.0.0.1:${PUBLIC_PORT}/upload-progress"
fi
echo "DataRoot          : $DATA_ROOT"
echo "InfoFile          : $DESKTOP_INFO_FILE"
