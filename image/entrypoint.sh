#!/bin/bash
set -u

APP=/opt/apps/yunshu/files
BIN="${APP}/bin"
STATE="${YUNSHU_STATE_DIR:-/var/lib/yunshu}"
SEED=/usr/local/share/yunshu

CORP_CODE="${YUNSHU_CORP_CODE:-}"
SP_ADDR="${YUNSHU_SP_ADDR:-https://sp.eagleyun.cn/}"
LOGIN_ON_START="${YUNSHU_LOGIN_ON_START:-1}"
HTTP_ADDR="${YUNSHU_LOGIN_HTTP_ADDR:-}"
HTTP_PORT="${YUNSHU_LOGIN_HTTP_PORT:-8080}"
MARKER="${STATE}/config/.logged-in"

_children=""

_term() {
    trap - TERM INT
    [ -n "${_children}" ] && kill ${_children} 2>/dev/null
    wait
    exit 0
}
trap _term TERM INT

_supervise() {
    _name="$1"; shift
    _log="${STATE}/logs/${_name}.log"
    (
        while :; do
            "$@" >>"${_log}" 2>&1
            _rc=$?
            echo "[entrypoint] ${_name} exited rc=${_rc}" >>"${_log}"
            [ "${_rc}" -eq 0 ] && break
            sleep 5
        done
    ) &
    _children="${_children} $!"
}

_init() {
    mkdir -p "${STATE}/config" "${STATE}/socket" "${STATE}/tmp" \
             "${STATE}/bak" "${STATE}/logs" "${STATE}/login-www"
    chmod 0755 "${STATE}/socket" "${STATE}/tmp" "${STATE}/bak" "${STATE}/logs"

    if [ ! -f "${STATE}/config/version.ini" ]; then
        cp "${SEED}/version.ini" "${STATE}/config/version.ini"
    fi

    if [ ! -f "${STATE}/config/private_ctl.conf" ]; then
        printf '%s\n' "${SP_ADDR}" > "${STATE}/config/private_ctl.conf"
    fi

    if [ ! -f "${STATE}/config/app_config.json" ]; then
        printf '{\n  "corpcode": "%s",\n  "sp_addr": "%s"\n}\n' \
            "${CORP_CODE}" "${SP_ADDR}" > "${STATE}/config/app_config.json"
    fi
}

_init

if [ "${LOGIN_ON_START}" = "1" ] && [ ! -f "${MARKER}" ]; then
    _supervise login /usr/local/bin/yunshu-login.sh
fi

if [ "${LOGIN_ON_START}" = "1" ]; then
    if [ -n "${HTTP_ADDR}" ] && [ "${HTTP_ADDR}" != "0.0.0.0" ]; then
        _supervise login-http /usr/sbin/mini_httpd -D -u root -p "${HTTP_PORT}" -h "${HTTP_ADDR}" -d "${STATE}/login-www"
    else
        _supervise login-http /usr/sbin/mini_httpd -D -u root -p "${HTTP_PORT}" -d "${STATE}/login-www"
    fi
    _supervise connect /usr/local/bin/yunshu-connect.sh
fi

_supervise daemon "${BIN}/yunshu-daemon"
_supervise updater "${BIN}/yunshu-updater"

wait
