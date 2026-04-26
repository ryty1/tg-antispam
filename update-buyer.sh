#!/usr/bin/env bash
set -euo pipefail

REPO="ryty1/tg-antispam"
APP_DIR="/opt/tg-antispam"
RELEASE_DIR="${APP_DIR}/release"
PROCESS_NAME="tg-buyer"
BIN_NAME="app.protected.buyer.cjs"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
ENV_FILE="${APP_DIR}/.env"
LOCK_FILE="/tmp/tg-buyer-update.lock"
WORKER_LOG="/tmp/tg-buyer-update-worker.log"

read_env_value() {
  local key="$1"
  if [[ ! -f "${ENV_FILE}" ]]; then
    printf ""
    return
  fi
  local line
  line="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 || true)"
  printf "%s" "${line#*=}"
}

notify_tg() {
  local text="$(printf '%b' "$1")"
  local token="${BOT_TOKEN:-}"
  local chat_id="${ADMIN_USER_ID:-}"
  if [[ -z "${token}" ]]; then
    token="$(read_env_value BOT_TOKEN)"
  fi
  if [[ -z "${chat_id}" ]]; then
    chat_id="$(read_env_value ADMIN_USER_ID)"
  fi
  if [[ -z "${token}" || -z "${chat_id}" ]]; then
    return 0
  fi
  curl -fsS -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "text=${text}" \
    --data-urlencode "disable_web_page_preview=true" \
    >/dev/null 2>&1 || true
}

fetch_latest_tag() {
  local tag=""
  tag="$(curl -fsSL --max-time 8 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/' || true)"
  printf "%s" "${tag}"
}

run_worker_detached() {
  if command -v setsid >/dev/null 2>&1; then
    setsid env TG_BUYER_UPDATE_WORKER=1 bash "$0" --worker >"${WORKER_LOG}" 2>&1 < /dev/null &
  else
    nohup env TG_BUYER_UPDATE_WORKER=1 bash "$0" --worker >"${WORKER_LOG}" 2>&1 < /dev/null &
  fi
  echo "[update] worker started: ${WORKER_LOG}"
}

if [[ "${1:-}" != "--worker" ]]; then
  echo "[update] scheduling detached worker..."
  run_worker_detached
  exit 0
fi

TMP_DIR="$(mktemp -d)"
LATEST_TAG="$(fetch_latest_tag)"

cleanup() {
  rm -rf "${TMP_DIR}"
  rm -f "${LOCK_FILE}"
}
trap cleanup EXIT

if [[ -e "${LOCK_FILE}" ]]; then
  echo "[update] another update is running"
  exit 1
fi
touch "${LOCK_FILE}"

mkdir -p "${RELEASE_DIR}"
cd "${TMP_DIR}"

echo "[update] downloading assets..."
curl -fL --retry 3 --retry-delay 2 "${BASE_URL}/${BIN_NAME}" -o "${BIN_NAME}"
curl -fL --retry 3 --retry-delay 2 "${BASE_URL}/${BIN_NAME}.sha256" -o "${BIN_NAME}.sha256"

echo "[update] verifying checksum..."
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c "${BIN_NAME}.sha256"
else
  expected="$(awk '{print $1}' "${BIN_NAME}.sha256")"
  actual="$(shasum -a 256 "${BIN_NAME}" | awk '{print $1}')"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "[update] sha256 mismatch"
    exit 1
  fi
fi

expected_hash="$(awk '{print $1}' "${BIN_NAME}.sha256" | tr -d ' \r\n')"
if command -v sha256sum >/dev/null 2>&1; then
  downloaded_hash="$(sha256sum "${BIN_NAME}" | awk '{print $1}' | tr -d ' \r\n')"
else
  downloaded_hash="$(shasum -a 256 "${BIN_NAME}" | awk '{print $1}' | tr -d ' \r\n')"
fi

if [[ -f "${RELEASE_DIR}/${BIN_NAME}" ]]; then
  if command -v sha256sum >/dev/null 2>&1; then
    current_hash="$(sha256sum "${RELEASE_DIR}/${BIN_NAME}" | awk '{print $1}' | tr -d ' \r\n')"
  else
    current_hash="$(shasum -a 256 "${RELEASE_DIR}/${BIN_NAME}" | awk '{print $1}' | tr -d ' \r\n')"
  fi
  echo "[update] local_hash=${current_hash}"
  echo "[update] remote_hash=${downloaded_hash}"
  if [[ -n "${downloaded_hash}" && "${current_hash}" == "${downloaded_hash}" ]]; then
    echo "[update] already latest binary, skip replace/restart"
    notify_tg "ℹ️ 已是最新版本\n版本: ${LATEST_TAG:-未知}\n远端哈希: ${downloaded_hash}\n本地哈希: ${current_hash}\n无需重复更新"
    exit 0
  fi
fi

backup_file="${RELEASE_DIR}/${BIN_NAME}.bak.$(date +%Y%m%d%H%M%S)"
if [[ -f "${RELEASE_DIR}/${BIN_NAME}" ]]; then
  cp -f "${RELEASE_DIR}/${BIN_NAME}" "${backup_file}"
fi

echo "[update] replacing binary..."
install -m 0644 "${BIN_NAME}" "${RELEASE_DIR}/${BIN_NAME}"

echo "[update] restarting pm2 process ${PROCESS_NAME}..."
if pm2 restart "${PROCESS_NAME}" --update-env; then
  sleep 2
  pm2 describe "${PROCESS_NAME}" >/dev/null
  notify_tg "✅ 更新完成\n版本: ${LATEST_TAG:-未知}\n状态: 脚本执行成功并已重启"
  echo "[update] success"
  exit 0
fi

echo "[update] restart failed, rolling back..."
if [[ -f "${backup_file}" ]]; then
  cp -f "${backup_file}" "${RELEASE_DIR}/${BIN_NAME}"
  pm2 restart "${PROCESS_NAME}" --update-env || true
fi
notify_tg "❌ 更新失败\n版本: ${LATEST_TAG:-未知}\n请登录服务器查看日志: ${WORKER_LOG}"
exit 1
