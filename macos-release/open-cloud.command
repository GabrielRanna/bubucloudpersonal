#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
. "$SCRIPT_DIR/common.sh"

public_url="$(quick_tunnel_url 2>/dev/null || true)"
if [[ -n "$public_url" ]]; then
  open_cloud_url "${public_url}/upload-progress"
else
  open_cloud_url "http://127.0.0.1:${PUBLIC_PORT}/upload-progress"
fi
