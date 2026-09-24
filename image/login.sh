#!/bin/bash
set -u

STATE="${YUNSHU_STATE_DIR:-/var/lib/yunshu}"
BIN="${YUNSHU_BIN:-/opt/apps/yunshu/files/bin/yunshu}"
CORP_CODE="${YUNSHU_CORP_CODE:-}"

WWW="${STATE}/login-www"
LOG="${STATE}/logs/login.log"
URL_FILE="${WWW}/login-url.txt"
STATUS_FILE="${WWW}/status.json"
INDEX_FILE="${WWW}/index.html"
MARKER="${STATE}/config/.logged-in"

mkdir -p "${WWW}" "${STATE}/config"

_esc_html() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

_esc_json() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

_write_status() {
    printf '{"url":"%s","status":"%s","detail":"%s"}\n' \
        "$(_esc_json "$3")" "$1" "$2" > "${STATUS_FILE}"
}

_render() {
    _status="$1"
    _url="$2"
    case "${_status}" in
        authenticated) _text="登录成功" ;;
        error)         _text="登录失败" ;;
        *)             _text="等待登录" ;;
    esac
    if [ -n "${_url}" ]; then
        _a="$(_esc_html "${_url}")"
        _link="<p><a href=\"${_a}\">打开飞书 SSO 登录页</a></p><p><code>${_a}</code></p>"
    else
        _link="<p>正在获取登录链接，请稍候…</p>"
    fi
    printf '%s\n' \
        '<!doctype html>' \
        '<html lang="zh-CN">' \
        '<meta charset="utf-8">' \
        '<meta http-equiv="refresh" content="3">' \
        '<title>YunShu 登录</title>' \
        '<body>' \
        '<h1>YunShu 登录</h1>' \
        "<p>状态：${_text}</p>" \
        "${_link}" \
        '<hr>' \
        '<p>完成飞书 SSO 后本页自动刷新。</p>' \
        '</body>' \
        '</html>' \
        > "${INDEX_FILE}"
}

if [ -z "${CORP_CODE}" ]; then
    echo "[login] YUNSHU_CORP_CODE 未设置" >&2
    _write_status error "YUNSHU_CORP_CODE 未设置" ""
    _render error ""
    sleep 30
    exit 1
fi

: > "${URL_FILE}"
_write_status waiting "" ""
_render waiting ""

echo "[login] 正在获取飞书 SSO 登录链接（企业码 ${CORP_CODE}）..."

printf '1\n' | "${BIN}" -c "${CORP_CODE}" -l 2>&1 | while IFS= read -r _line_; do
    printf '%s\n' "${_line_}" >> "${LOG}"
    printf '%s\n' "${_line_}"
    if [ ! -s "${URL_FILE}" ]; then
        _cand_="$(printf '%s\n' "${_line_}" | grep -Eo 'https?://[^[:space:]]+' | head -n1 || true)"
        if [ -n "${_cand_}" ]; then
            printf '%s\n' "${_cand_}" > "${URL_FILE}"
            _write_status waiting "" "${_cand_}"
            _render waiting "${_cand_}"
            echo "[login] 登录链接: ${_cand_}" >&2
        fi
    fi
done
_rc="${PIPESTATUS[1]:-1}"
_url="$(cat "${URL_FILE}" 2>/dev/null || true)"

if [ "${_rc}" -eq 0 ]; then
    touch "${MARKER}"
    _write_status authenticated "login succeeded" "${_url}"
    _render authenticated "${_url}"
    echo "[login] 登录成功"
else
    _write_status error "yunshu exited with ${_rc}" "${_url}"
    _render error "${_url}"
    echo "[login] 登录失败（rc=${_rc}），登录链接: ${_url}" >&2
fi

sleep 3
exit "${_rc}"
