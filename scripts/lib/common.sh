#!/usr/bin/env bash

APP_NAME="metatube"
SERVICE_NAME="metatube"
SERVICE_USER="metatube"
INSTALL_ROOT="/opt/metatube"
BIN_DIR="$INSTALL_ROOT/bin"
BIN_PATH="$BIN_DIR/metatube-server"
LAUNCHER_PATH="$BIN_DIR/start-metatube.sh"
INSTALLER_DIR="$INSTALL_ROOT/installer"
UPDATER_PATH="$INSTALLER_DIR/update.sh"
CONFIG_DIR="/etc/metatube"
ENV_FILE="$CONFIG_DIR/metatube.env"
STATE_DIR="/var/lib/metatube"
DB_PATH="$STATE_DIR/metatube.db"
BACKUP_DIR="$STATE_DIR/backups"
LOG_DIR="/var/log/metatube"
INSTALL_LOG="$LOG_DIR/install.log"
UPDATE_LOG="$LOG_DIR/update.log"
TMP_DIR="/tmp/metatube-installer"
CRON_FILE="/etc/cron.d/metatube"
UNIT_FILE="/etc/systemd/system/metatube.service"
VERSION_FILE="$INSTALL_ROOT/VERSION"
DEFAULT_PORT="8080"
REPO_API="https://api.github.com/repos/metatube-community/metatube-server-releases/releases/latest"
ASSET_NAME="metatube-server-linux-amd64-v3.zip"

log_ts() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
  printf '[%s] [INFO] %s\n' "$(log_ts)" "$*"
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(log_ts)" "$*" >&2
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(log_ts)" "$*" >&2
}

fail() {
  log_error "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "需要 root 权限执行。"
}

get_os_id_from_text() {
  local content="$1"
  local id_value
  id_value="$(printf '%s\n' "$content" | grep -E '^ID=' | head -n1 | cut -d'=' -f2 | tr -d '"')"
  printf '%s\n' "$id_value"
}

is_supported_os_id() {
  local os_id="$1"
  [[ "$os_id" == "debian" || "$os_id" == "ubuntu" ]]
}

ensure_supported_os() {
  [[ -f /etc/os-release ]] || fail "未找到 /etc/os-release，无法识别系统。"

  local os_id
  os_id="$(get_os_id_from_text "$(< /etc/os-release)")"

  if ! is_supported_os_id "$os_id"; then
    fail "仅支持 Debian/Ubuntu，当前系统：${os_id:-unknown}。"
  fi

  log_info "系统检查通过：$os_id"
}

required_v3_flags() {
  printf '%s\n' lahf_lm popcnt ssse3 sse4_1 sse4_2 cx16 avx avx2 bmi1 bmi2 f16c fma abm movbe xsave
}

missing_v3_flags() {
  local flags_line="$1"
  local missing=()
  local flag

  while IFS= read -r flag; do
    [[ -z "$flag" ]] && continue
    if [[ " $flags_line " != *" $flag "* ]]; then
      missing+=("$flag")
    fi
  done < <(required_v3_flags)

  printf '%s\n' "${missing[*]}"
}

ensure_v3_cpu() {
  local arch flags_line missing
  arch="$(uname -m)"
  [[ "$arch" == "x86_64" ]] || fail "仅支持 x86_64，当前架构：$arch。"

  flags_line="$(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2-)"
  [[ -n "$flags_line" ]] || fail "无法读取 CPU flags。"

  missing="$(missing_v3_flags "$flags_line")"
  [[ -z "$missing" ]] || fail "CPU 不满足 linux-amd64-v3 要求，缺少：$missing"

  log_info "CPU 检查通过：支持 linux-amd64-v3"
}

ensure_dependencies() {
  local missing_packages=()
  local package

  if ! command_exists curl; then missing_packages+=(curl); fi
  if ! command_exists jq; then missing_packages+=(jq); fi
  if ! command_exists unzip; then missing_packages+=(unzip); fi
  if ! command_exists sqlite3; then missing_packages+=(sqlite3); fi
  if ! command_exists openssl; then missing_packages+=(openssl); fi
  if ! command_exists systemctl; then missing_packages+=(systemd); fi
  if ! command_exists crontab; then missing_packages+=(cron); fi

  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    log_info "开始安装依赖：${missing_packages[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates "${missing_packages[@]}"
  fi

  for package in curl jq unzip sqlite3 openssl systemctl crontab; do
    command_exists "$package" || fail "依赖未安装成功：$package"
  done

  log_info "依赖检查通过"
}

ensure_service_user() {
  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --home-dir "$STATE_DIR" --create-home --shell /usr/sbin/nologin "$SERVICE_USER"
    log_info "已创建服务用户：$SERVICE_USER"
  fi
}

ensure_runtime_directories() {
  mkdir -p "$BIN_DIR" "$INSTALLER_DIR/scripts/lib" "$CONFIG_DIR" "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR" "$TMP_DIR"
  chown -R "$SERVICE_USER":"$SERVICE_USER" "$STATE_DIR" "$LOG_DIR"
  chmod 0755 "$INSTALL_ROOT" "$BIN_DIR" "$INSTALLER_DIR" "$INSTALLER_DIR/scripts" "$INSTALLER_DIR/scripts/lib" "$CONFIG_DIR" "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR"
}

setup_install_logging() {
  mkdir -p "$LOG_DIR"
  touch "$INSTALL_LOG"
  chmod 0644 "$INSTALL_LOG"
  exec > >(tee -a "$INSTALL_LOG") 2> >(tee -a "$INSTALL_LOG" >&2)
}

setup_update_logging() {
  mkdir -p "$LOG_DIR"
  touch "$UPDATE_LOG"
  chmod 0644 "$UPDATE_LOG"
  exec > >(tee -a "$UPDATE_LOG") 2> >(tee -a "$UPDATE_LOG" >&2)
}

generate_token() {
  openssl rand -hex 32
}

read_env_value() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  grep -E "^${key}=" "$file" | head -n1 | cut -d'=' -f2-
}

render_env_file() {
  local token="$1"
  cat <<EOF
TOKEN=$token
PORT=$DEFAULT_PORT
DSN=$DB_PATH
DB_AUTO_MIGRATE=true
EOF
}

ensure_env_file() {
  local token
  local previous_umask
  token="$(read_env_value TOKEN "$ENV_FILE")"

  if [[ -z "$token" ]]; then
    token="$(generate_token)"
    log_info "未发现 TOKEN，已自动生成。"
  else
    log_info "检测到已有 TOKEN，保留原值。"
  fi

  previous_umask="$(umask)"
  umask 077
  render_env_file "$token" > "$ENV_FILE"
  umask "$previous_umask"
  chown root:"$SERVICE_USER" "$ENV_FILE"
  chmod 0640 "$ENV_FILE"
}

write_file() {
  local path="$1"
  local content="$2"
  printf '%s' "$content" > "$path"
}

install_binary_from_archive() {
  local archive_path="$1"
  local extract_dir="$TMP_DIR/extracted"
  local expected_binary_name fallback_binary_name extracted_binary matched_binaries
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  unzip -oq "$archive_path" -d "$extract_dir"

  expected_binary_name="${ASSET_NAME%.zip}"
  fallback_binary_name="metatube-server"

  extracted_binary="$(find "$extract_dir" -type f -name "$expected_binary_name" | head -n1)"

  if [[ -z "$extracted_binary" ]]; then
    extracted_binary="$(find "$extract_dir" -type f -name "$fallback_binary_name" | head -n1)"
  fi

  if [[ -z "$extracted_binary" ]]; then
    matched_binaries="$(find "$extract_dir" -type f -name 'metatube-server*')"
    if [[ -n "$matched_binaries" && "$(printf '%s\n' "$matched_binaries" | wc -l)" -eq 1 ]]; then
      extracted_binary="$matched_binaries"
    fi
  fi

  [[ -n "$extracted_binary" ]] || fail "压缩包中未找到可安装二进制。"

  install -m 0755 "$extracted_binary" "$BIN_PATH"
  log_info "二进制已安装：$BIN_PATH"
}

render_launcher_script() {
  cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

set -a
source /etc/metatube/metatube.env
set +a

args=("-dsn" "${DSN}" "-port" "${PORT}")

if [[ "${DB_AUTO_MIGRATE:-false}" == "true" ]]; then
  args+=("-db-auto-migrate")
fi

exec /opt/metatube/bin/metatube-server "${args[@]}"
EOF
}

install_launcher_script() {
  render_launcher_script > "$LAUNCHER_PATH"
  chmod 0755 "$LAUNCHER_PATH"
}

install_updater_bundle() {
  local source_root="$1"
  install -m 0755 "$source_root/update.sh" "$UPDATER_PATH"
  install -m 0644 "$source_root/scripts/lib/common.sh" "$INSTALLER_DIR/scripts/lib/common.sh"
  install -m 0644 "$source_root/scripts/lib/github.sh" "$INSTALLER_DIR/scripts/lib/github.sh"
  install -m 0644 "$source_root/scripts/lib/systemd.sh" "$INSTALLER_DIR/scripts/lib/systemd.sh"
}

write_installed_version() {
  local tag_name="$1"
  printf '%s\n' "$tag_name" > "$VERSION_FILE"
}

read_installed_version() {
  [[ -f "$VERSION_FILE" ]] || fail "未找到已安装版本记录，请先执行 install.sh。"
  tr -d '[:space:]' < "$VERSION_FILE"
}

assert_existing_installation() {
  [[ -x "$BIN_PATH" ]] || fail "未检测到已安装二进制，请先执行 install.sh。"
  [[ -f "$ENV_FILE" ]] || fail "未检测到配置文件，请先执行 install.sh。"
}

backup_database_if_present() {
  if [[ -f "$DB_PATH" ]]; then
    local backup_path="$BACKUP_DIR/metatube-$(date '+%Y%m%d%H%M%S').db"
    cp "$DB_PATH" "$backup_path"
    chown "$SERVICE_USER":"$SERVICE_USER" "$backup_path"
    log_info "已备份数据库：$backup_path"
  else
    log_warn "数据库文件不存在，跳过备份。"
  fi
}

verify_runtime_state() {
  [[ -x "$BIN_PATH" ]] || fail "二进制不存在或不可执行。"
  [[ -f "$ENV_FILE" ]] || fail "配置文件不存在。"
  [[ -f "$UNIT_FILE" ]] || fail "systemd 服务文件不存在。"
  [[ -f "$CRON_FILE" ]] || fail "cron 配置不存在。"
  systemctl is-active --quiet "$SERVICE_NAME" || fail "MetaTube 服务未成功启动。"
  log_info "运行状态检查通过"
}
