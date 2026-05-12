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
  assert_existing_installation
  setup_update_logging

  local release_json latest_tag asset_url asset_digest archive_path current_version previous_binary previous_version service_was_active
  release_json="$(fetch_latest_release_json)"
  latest_tag="$(extract_latest_tag "$release_json")"
  asset_url="$(extract_asset_url "$release_json" "$ASSET_NAME")"
  asset_digest="$(extract_asset_digest "$release_json" "$ASSET_NAME")"
  archive_path="$TMP_DIR/$ASSET_NAME"
  current_version="$(read_installed_version)"

  if [[ "$current_version" == "$latest_tag" ]]; then
    log_info "当前已是最新版本：$current_version"
    exit 0
  fi

  log_info "检测到新版本：$current_version -> $latest_tag"
  download_release_asset "$asset_url" "$archive_path"
  verify_archive_digest "$archive_path" "$asset_digest"

  previous_binary="$TMP_DIR/metatube-server.previous"
  cp "$BIN_PATH" "$previous_binary"
  previous_version="$current_version"
  service_was_active="false"

  if systemctl is-active --quiet "$SERVICE_NAME"; then
    service_was_active="true"
  fi

  rollback_update() {
    local exit_code=$?
    log_error "更新失败，开始回滚。"

    if [[ -f "$previous_binary" ]]; then
      install -m 0755 "$previous_binary" "$BIN_PATH"
    fi

    if [[ -n "${previous_version:-}" ]]; then
      write_installed_version "$previous_version"
    fi

    if [[ "${service_was_active:-false}" == "true" ]]; then
      systemctl restart "$SERVICE_NAME" || true
    fi

    exit "$exit_code"
  }

  trap rollback_update ERR

  stop_metatube_service_if_present
  backup_database_if_present
  install_binary_from_archive "$archive_path"
  write_installed_version "$latest_tag"
  enable_and_restart_metatube_service
  verify_runtime_state
  trap - ERR

  log_info "更新完成。当前版本：$latest_tag"
}

main "$@"
