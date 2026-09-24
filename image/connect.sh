#!/bin/bash
set -u

STATE="${YUNSHU_STATE_DIR:-/var/lib/yunshu}"
BIN="${YUNSHU_BIN:-/opt/apps/yunshu/files/bin/yunshu}"
MARKER="${STATE}/config/.logged-in"
INTERVAL="${YUNSHU_CONNECT_INTERVAL:-15}"

while :; do
    if [ -f "${MARKER}" ]; then
        if "${BIN}" -i 2>&1 | grep -q "已断开"; then
            echo "[connect] 已登录但连接断开，执行 yunshu -s all"
            "${BIN}" -s all || true
        fi
    fi
    sleep "${INTERVAL}"
done
