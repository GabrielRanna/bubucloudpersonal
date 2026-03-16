#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
BIN_DIR="$BASE_DIR/bin"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
DATA_ROOT="${PERSONAL_CLOUD_DATA_ROOT:-$HOME/CloudDrive}"
CREDENTIALS_FILE="$BASE_DIR/credentials.txt"
STATUS_FILE="$BASE_DIR/connection-info.txt"
DESKTOP_DIR="${HOME}/Desktop"
if [[ ! -d "$DESKTOP_DIR" ]]; then
  DESKTOP_DIR="$BASE_DIR"
fi
DESKTOP_INFO_FILE="$DESKTOP_DIR/MINHA-NUVEM.txt"
DESKTOP_OPEN_SCRIPT="$DESKTOP_DIR/ABRIR-MINHA-NUVEM.command"
WELCOME_FILE="$DATA_ROOT/0-COMECE-AQUI.txt"
GATEWAY_SCRIPT="$BASE_DIR/gateway.py"
PUBLIC_URL_MONITOR_LOG="$LOG_DIR/public-url-monitor.log"

USERNAME="cloud"
PUBLIC_PORT="8394"
FILEBROWSER_PORT="8396"
CLOUDFLARED_METRICS_PORT="8395"

FILEBROWSER_DIR="$BIN_DIR/filebrowser"
FILEBROWSER_EXE="$FILEBROWSER_DIR/filebrowser"
FILEBROWSER_DB="$CONFIG_DIR/filebrowser.db"
FILEBROWSER_PID_FILE="$CONFIG_DIR/filebrowser.pid"
FILEBROWSER_STDOUT_LOG="$LOG_DIR/filebrowser.stdout.log"
FILEBROWSER_STDERR_LOG="$LOG_DIR/filebrowser.stderr.log"

CLOUDFLARED_EXE="$BIN_DIR/cloudflared"
CLOUDFLARED_PID_FILE="$CONFIG_DIR/cloudflared.pid"
CLOUDFLARED_STDOUT_LOG="$LOG_DIR/cloudflared.stdout.log"
CLOUDFLARED_STDERR_LOG="$LOG_DIR/cloudflared.stderr.log"

GATEWAY_PID_FILE="$CONFIG_DIR/gateway.pid"
GATEWAY_STDOUT_LOG="$LOG_DIR/gateway.log"
GATEWAY_STDERR_LOG="$LOG_DIR/gateway.stderr.log"

PYTHON_EXE=""

log() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

detect_python() {
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_EXE="$(command -v python3)"
    return
  fi
  if command -v python >/dev/null 2>&1; then
    PYTHON_EXE="$(command -v python)"
    return
  fi
  fail "Python nao encontrado. Instale python3 antes de usar a release de macOS."
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    arm64|aarch64) printf 'arm64' ;;
    *) printf 'amd64' ;;
  esac
}

ensure_dirs() {
  mkdir -p "$BASE_DIR" "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$DATA_ROOT"
}

new_internal_password() {
  python3 - <<'PY'
import secrets
print("Pc!" + secrets.token_urlsafe(24) + "Aa1")
PY
}

public_password() {
  printf '1987'
}

setting_value() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 1
  python3 - "$key" "$file" <<'PY'
import sys
key, path = sys.argv[1], sys.argv[2]
prefix = key + ":"
for line in open(path, encoding="ascii", errors="ignore"):
    if line.startswith(prefix):
        print(line.split(":", 1)[1].strip())
        raise SystemExit(0)
raise SystemExit(1)
PY
}

ensure_credentials() {
  ensure_dirs

  local public_pwd internal_pwd
  public_pwd="$(setting_value "Senha" "$CREDENTIALS_FILE" 2>/dev/null || true)"
  internal_pwd="$(setting_value "SenhaInternaFileBrowser" "$CREDENTIALS_FILE" 2>/dev/null || true)"

  [[ -n "$public_pwd" ]] || public_pwd="$(public_password)"
  [[ -n "$internal_pwd" ]] || internal_pwd="$(new_internal_password)"

  cat >"$CREDENTIALS_FILE" <<EOF
Nuvem Pessoal
Usuario: $USERNAME
Senha: $public_pwd
SenhaInternaFileBrowser: $internal_pwd
Pasta da nuvem: $DATA_ROOT
Arquivo de status: $DESKTOP_INFO_FILE
EOF
}

stored_password() {
  setting_value "Senha" "$CREDENTIALS_FILE"
}

stored_internal_password() {
  setting_value "SenhaInternaFileBrowser" "$CREDENTIALS_FILE"
}

write_open_script() {
  cat >"$DESKTOP_OPEN_SCRIPT" <<EOF
#!/bin/bash
cd "$BASE_DIR"
"$BASE_DIR/open-cloud.command"
EOF
  chmod +x "$DESKTOP_OPEN_SCRIPT"
}

write_connection_info() {
  local public_url="${1:-}"
  local password upload_url
  password="$(stored_password 2>/dev/null || true)"
  if [[ -n "$public_url" ]]; then
    upload_url="${public_url}/upload-progress"
  else
    upload_url="http://127.0.0.1:${PUBLIC_PORT}/upload-progress"
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  cat >"$tmp_file" <<EOF
Nuvem Pessoal
Atualizado: $(date '+%Y-%m-%d %H:%M:%S')

Plataforma: macos
Pasta da nuvem: $DATA_ROOT
URL local: http://127.0.0.1:${PUBLIC_PORT}
URL publica: ${public_url:-indisponivel no momento}
URL upload com progresso: $upload_url

Usuario: $USERNAME
Senha: ${password:-veja credentials.txt}

Observacao: a URL publica pode mudar se o processo do tunnel reiniciar.
Observacao: o Mac precisa ficar ligado e com a sessao do usuario ativa.
EOF

  cp "$tmp_file" "$STATUS_FILE"
  cp "$tmp_file" "$DESKTOP_INFO_FILE"
  cp "$tmp_file" "$WELCOME_FILE"
  rm -f "$tmp_file"
  write_open_script
}

read_pid() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  tr -d '[:space:]' <"$pid_file"
}

pid_alive() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

cleanup_pid_file() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] && rm -f "$pid_file"
}

stop_pid_file() {
  local pid_file="$1"
  local pid
  pid="$(read_pid "$pid_file" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && pid_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    if pid_alive "$pid"; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  cleanup_pid_file "$pid_file"
}

stop_process_by_hint() {
  local process_name="$1"
  local hint="$2"
  local pids
  pids="$(ps ax -o pid= -o command= | grep "$process_name" | grep "$hint" | grep -v grep | awk '{print $1}' || true)"
  if [[ -n "$pids" ]]; then
    while read -r pid; do
      [[ -n "$pid" ]] || continue
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
    done <<<"$pids"
  fi
}

quick_tunnel_url() {
  python3 - "$CLOUDFLARED_STDOUT_LOG" "$CLOUDFLARED_STDERR_LOG" <<'PY'
import pathlib, re, sys
pattern = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")
for path in map(pathlib.Path, sys.argv[1:]):
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    matches = pattern.findall(text)
    if matches:
        print(matches[-1])
        raise SystemExit(0)
raise SystemExit(1)
PY
}

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "Comando obrigatorio nao encontrado: $name"
}

download_file() {
  local url="$1"
  local dest="$2"
  curl -L --fail --silent --show-error "$url" -o "$dest"
}

install_filebrowser() {
  ensure_dirs
  if [[ -x "$FILEBROWSER_EXE" ]]; then
    log "File Browser ja esta presente em $FILEBROWSER_EXE"
    return
  fi

  require_command curl
  require_command tar
  local asset archive extract_dir arch
  arch="$(detect_arch)"
  if [[ "$arch" == "arm64" ]]; then
    asset="darwin-arm64-filebrowser.tar.gz"
  else
    asset="darwin-amd64-filebrowser.tar.gz"
  fi
  archive="$BIN_DIR/$asset"
  extract_dir="$BIN_DIR/filebrowser-extract"

  rm -rf "$archive" "$extract_dir" "$FILEBROWSER_DIR"
  log "Baixando File Browser: $asset"
  download_file "https://github.com/filebrowser/filebrowser/releases/latest/download/$asset" "$archive"
  mkdir -p "$extract_dir" "$FILEBROWSER_DIR"
  tar -xzf "$archive" -C "$extract_dir"
  mv "$extract_dir/filebrowser" "$FILEBROWSER_EXE"
  chmod +x "$FILEBROWSER_EXE"
  rm -rf "$archive" "$extract_dir"
}

install_cloudflared() {
  ensure_dirs
  if [[ -x "$CLOUDFLARED_EXE" ]]; then
    log "cloudflared ja esta presente em $CLOUDFLARED_EXE"
    return
  fi

  require_command curl
  require_command tar
  local asset archive extract_dir arch
  arch="$(detect_arch)"
  if [[ "$arch" == "arm64" ]]; then
    asset="cloudflared-darwin-arm64.tgz"
  else
    asset="cloudflared-darwin-amd64.tgz"
  fi
  archive="$BIN_DIR/$asset"
  extract_dir="$BIN_DIR/cloudflared-extract"

  rm -rf "$archive" "$extract_dir" "$CLOUDFLARED_EXE"
  log "Baixando cloudflared: $asset"
  download_file "https://github.com/cloudflare/cloudflared/releases/latest/download/$asset" "$archive"
  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  mv "$extract_dir/cloudflared" "$CLOUDFLARED_EXE"
  chmod +x "$CLOUDFLARED_EXE"
  rm -rf "$archive" "$extract_dir"
}

install_dependencies() {
  detect_python
  install_filebrowser
  install_cloudflared
}

filebrowser_cli() {
  "$FILEBROWSER_EXE" "$@" >/dev/null
}

ensure_database() {
  local internal_pwd
  internal_pwd="$(stored_internal_password)"

  if [[ ! -f "$FILEBROWSER_DB" ]]; then
    filebrowser_cli config init \
      -d "$FILEBROWSER_DB" \
      -r "$DATA_ROOT" \
      -a "127.0.0.1" \
      -p "$FILEBROWSER_PORT" \
      --branding.name "Bubu Drive" \
      --branding.disableExternal \
      --locale "pt-br" \
      --signup
    filebrowser_cli users add "$USERNAME" "$internal_pwd" \
      --perm.admin \
      --locale "pt-br" \
      --scope "/" \
      -d "$FILEBROWSER_DB"
    return
  fi

  filebrowser_cli config set \
    -d "$FILEBROWSER_DB" \
    -r "$DATA_ROOT" \
    -a "127.0.0.1" \
    -p "$FILEBROWSER_PORT" \
    --branding.name "Bubu Drive" \
    --branding.disableExternal \
    --locale "pt-br" \
    --signup

  if ! filebrowser_cli users update "$USERNAME" \
    -p "$internal_pwd" \
    --locale "pt-br" \
    --scope "/" \
    --perm.admin \
    -d "$FILEBROWSER_DB"; then
    filebrowser_cli users add "$USERNAME" "$internal_pwd" \
      --perm.admin \
      --locale "pt-br" \
      --scope "/" \
      -d "$FILEBROWSER_DB"
  fi
}

bootstrap_release() {
  detect_python
  ensure_dirs
  ensure_credentials
  install_dependencies
  ensure_database
  write_connection_info ""
}

start_filebrowser() {
  if [[ -f "$FILEBROWSER_PID_FILE" ]] && pid_alive "$(read_pid "$FILEBROWSER_PID_FILE" 2>/dev/null || true)"; then
    return
  fi
  stop_process_by_hint "filebrowser" "$FILEBROWSER_DB"
  nohup "$FILEBROWSER_EXE" -d "$FILEBROWSER_DB" -a "127.0.0.1" -p "$FILEBROWSER_PORT" >"$FILEBROWSER_STDOUT_LOG" 2>"$FILEBROWSER_STDERR_LOG" &
  echo $! >"$FILEBROWSER_PID_FILE"
}

start_gateway() {
  if [[ -f "$GATEWAY_PID_FILE" ]] && pid_alive "$(read_pid "$GATEWAY_PID_FILE" 2>/dev/null || true)"; then
    return
  fi
  stop_process_by_hint "$(basename "$PYTHON_EXE")" "$GATEWAY_SCRIPT"
  nohup "$PYTHON_EXE" "$GATEWAY_SCRIPT" >"$GATEWAY_STDOUT_LOG" 2>"$GATEWAY_STDERR_LOG" &
  echo $! >"$GATEWAY_PID_FILE"
}

start_cloudflared() {
  if [[ -f "$CLOUDFLARED_PID_FILE" ]] && pid_alive "$(read_pid "$CLOUDFLARED_PID_FILE" 2>/dev/null || true)"; then
    return
  fi
  stop_process_by_hint "cloudflared" "127.0.0.1:${PUBLIC_PORT}"
  nohup "$CLOUDFLARED_EXE" tunnel --url "http://127.0.0.1:${PUBLIC_PORT}" --no-autoupdate --metrics "127.0.0.1:${CLOUDFLARED_METRICS_PORT}" --loglevel info >"$CLOUDFLARED_STDOUT_LOG" 2>"$CLOUDFLARED_STDERR_LOG" &
  echo $! >"$CLOUDFLARED_PID_FILE"
}

wait_for_local_url() {
  local url="$1"
  local attempts="${2:-30}"
  local i
  for ((i=0; i<attempts; i++)); do
    if curl -s --fail "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

open_cloud_url() {
  local url="$1"
  open "$url"
}
