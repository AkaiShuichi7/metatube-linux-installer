#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_ROOT=""
SCRIPT_DIR=""
REMOTE_BASE_URL="${METATUBE_INSTALLER_REMOTE_BASE_URL:-https://raw.githubusercontent.com/AkaiShuichi7/metatube-linux-installer/main}"

cleanup_bootstrap_root() {
  if [[ -n "$BOOTSTRAP_ROOT" && -d "$BOOTSTRAP_ROOT" ]]; then
    rm -rf "$BOOTSTRAP_ROOT"
  fi
}

download_bootstrap_file() {
  local relative_path="$1"
  local target_path="$2"

  curl -fsSL "$REMOTE_BASE_URL/$relative_path" -o "$target_path"
}

bootstrap_remote_tree() {
  command -v curl >/dev/null 2>&1 || {
    printf '[ERROR] 远程安装模式需要预先安装 curl。\n' >&2
    exit 1
  }

  BOOTSTRAP_ROOT="$(mktemp -d /tmp/metatube-installer-bootstrap.XXXXXX)"
  mkdir -p "$BOOTSTRAP_ROOT/scripts/lib"

  download_bootstrap_file "update.sh" "$BOOTSTRAP_ROOT/update.sh"
  download_bootstrap_file "scripts/lib/common.sh" "$BOOTSTRAP_ROOT/scripts/lib/common.sh"
  download_bootstrap_file "scripts/lib/github.sh" "$BOOTSTRAP_ROOT/scripts/lib/github.sh"
  download_bootstrap_file "scripts/lib/systemd.sh" "$BOOTSTRAP_ROOT/scripts/lib/systemd.sh"

  SCRIPT_DIR="$BOOTSTRAP_ROOT"
}

resolve_script_dir() {
  local script_path="${BASH_SOURCE[0]:-}"

  if [[ -n "$script_path" && -f "$script_path" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$script_path")" && pwd)"
    return 0
  fi

  bootstrap_remote_tree
}

trap cleanup_bootstrap_root EXIT

resolve_script_dir

source "$SCRIPT_DIR/scripts/lib/common.sh"
source "$SCRIPT_DIR/scripts/lib/github.sh"
source "$SCRIPT_DIR/scripts/lib/systemd.sh"

main() {
  require_root
  ensure_supported_os
  ensure_v3_cpu
  ensure_dependencies
  ensure_service_user
  ensure_runtime_directories
  setup_install_logging
  ensure_env_file

  local release_json tag_name asset_url asset_digest archive_path
  release_json="$(fetch_latest_release_json)"
  tag_name="$(extract_latest_tag "$release_json")"
  asset_url="$(extract_asset_url "$release_json" "$ASSET_NAME")"
  asset_digest="$(extract_asset_digest "$release_json" "$ASSET_NAME")"
  archive_path="$TMP_DIR/$ASSET_NAME"

  log_info "开始安装 MetaTube，目标版本：$tag_name"
  download_release_asset "$asset_url" "$archive_path"
  verify_archive_digest "$archive_path" "$asset_digest"
  install_binary_from_archive "$archive_path"
  write_installed_version "$tag_name"
  install_updater_bundle "$SCRIPT_DIR"
  install_launcher_script
  install_systemd_unit
  install_cron_file "$UPDATER_PATH"
  restart_cron_service
  enable_and_restart_metatube_service
  verify_runtime_state

  log_info "安装完成。版本：$tag_name"
  log_info "服务状态：systemctl status $SERVICE_NAME"
}

main "$@"
