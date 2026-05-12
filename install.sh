#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
