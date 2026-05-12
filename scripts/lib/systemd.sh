#!/usr/bin/env bash

render_systemd_unit() {
  cat <<EOF
[Unit]
Description=MetaTube 服务
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$STATE_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$LAUNCHER_PATH
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
}

render_cron_file() {
  local update_script_path="$1"
  cat <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

17 4 * * * root $update_script_path >> $UPDATE_LOG 2>&1
EOF
}

install_systemd_unit() {
  render_systemd_unit > "$UNIT_FILE"
  chmod 0644 "$UNIT_FILE"
  systemctl daemon-reload
}

install_cron_file() {
  local update_script_path="$1"
  render_cron_file "$update_script_path" > "$CRON_FILE"
  chmod 0644 "$CRON_FILE"
}

restart_cron_service() {
  systemctl enable --now cron
}

enable_and_restart_metatube_service() {
  systemctl enable --now "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

stop_metatube_service_if_present() {
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    systemctl stop "$SERVICE_NAME"
  fi
}
