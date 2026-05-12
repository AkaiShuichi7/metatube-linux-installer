#!/usr/bin/env bash

fetch_latest_release_json() {
  curl -fsSL "$REPO_API"
}

extract_latest_tag() {
  local release_json="$1"
  local tag_name
  tag_name="$(printf '%s' "$release_json" | jq -r '.tag_name // empty')"
  [[ -n "$tag_name" ]] || fail "无法从 GitHub API 解析 tag_name。"
  printf '%s\n' "$tag_name"
}

extract_asset_url() {
  local release_json="$1"
  local asset_name="$2"
  local asset_url
  asset_url="$(printf '%s' "$release_json" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .browser_download_url' | head -n1)"
  [[ -n "$asset_url" ]] || fail "未找到发布资产：$asset_name"
  printf '%s\n' "$asset_url"
}

extract_asset_digest() {
  local release_json="$1"
  local asset_name="$2"
  printf '%s' "$release_json" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .digest // empty' | head -n1
}

download_release_asset() {
  local asset_url="$1"
  local output_path="$2"
  mkdir -p "$(dirname "$output_path")"
  curl -fL "$asset_url" -o "$output_path"
  [[ -s "$output_path" ]] || fail "下载失败：$asset_url"
  log_info "下载完成：$output_path"
}

verify_archive_digest() {
  local archive_path="$1"
  local digest_value="$2"

  if [[ -z "$digest_value" ]]; then
    fail "发布资产未提供 digest，拒绝继续安装。"
  fi

  local expected actual
  expected="${digest_value#sha256:}"
  actual="$(sha256sum "$archive_path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "SHA256 校验失败。"
  log_info "SHA256 校验通过"
}
