#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
. "$SCRIPT_DIR/common.sh"

bootstrap_release
start_filebrowser
wait_for_local_url "http://127.0.0.1:${FILEBROWSER_PORT}" 30 || fail "File Browser interno nao iniciou corretamente."

start_gateway
wait_for_local_url "http://127.0.0.1:${PUBLIC_PORT}" 30 || fail "Gateway nao iniciou corretamente."

start_cloudflared

public_url=""
for _ in $(seq 1 45); do
  public_url="$(quick_tunnel_url 2>/dev/null || true)"
  [[ -n "$public_url" ]] && break
  sleep 2
done

write_connection_info "$public_url"

log "Local URL: http://127.0.0.1:${PUBLIC_PORT}"
if [[ -n "$public_url" ]]; then
  log "Public URL: $public_url"
  log "Upload URL: ${public_url}/upload-progress"
else
  log "Public URL: indisponivel no momento"
fi
