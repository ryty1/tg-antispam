#!/usr/bin/env bash
set -euo pipefail

REPO="ryty1/tg-antispam"
APP_DIR="/opt/tg-antispam"
RELEASE_DIR="${APP_DIR}/release"
PROCESS_NAME="tg-buyer"
BIN_NAME="app.protected.buyer.cjs"
BIN_SHA_NAME="${BIN_NAME}.sha256"
RUNTIME_PKG_NAME="buyer.runtime.tar.gz"
RUNTIME_PKG_SHA_NAME="${RUNTIME_PKG_NAME}.sha256"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
ENV_FILE="${APP_DIR}/.env"
LOCK_FILE="/tmp/tg-buyer-update.lock"
WORKER_LOG="/tmp/tg-buyer-update-worker.log"
RUNTIME_HASH_FILE="${RELEASE_DIR}/.buyer-runtime.sha256"

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

calc_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}' | tr -d ' \r\n'
  else
    shasum -a 256 "${file}" | awk '{print $1}' | tr -d ' \r\n'
  fi
}

verify_checksum() {
  local file="$1"
  local sha_file="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "${sha_file}"
  else
    local expected actual
    expected="$(awk '{print $1}' "${sha_file}")"
    actual="$(calc_sha256 "${file}")"
    if [[ "${expected}" != "${actual}" ]]; then
      echo "[update] sha256 mismatch: ${file}"
      exit 1
    fi
  fi
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
has_runtime_package="0"
if curl -fL --retry 3 --retry-delay 2 "${BASE_URL}/${RUNTIME_PKG_NAME}" -o "${RUNTIME_PKG_NAME}" \
  && curl -fL --retry 3 --retry-delay 2 "${BASE_URL}/${RUNTIME_PKG_SHA_NAME}" -o "${RUNTIME_PKG_SHA_NAME}"; then
  has_runtime_package="1"
  echo "[update] runtime package found: ${RUNTIME_PKG_NAME}"
else
  rm -f "${RUNTIME_PKG_NAME}" "${RUNTIME_PKG_SHA_NAME}"
  echo "[update] runtime package not found, fallback to binary-only update"
  curl -fL --retry 3 --retry-delay 2 "${BASE_URL}/${BIN_NAME}" -o "${BIN_NAME}"
  curl -fL --retry 3 --retry-delay 2 "${BASE_URL}/${BIN_SHA_NAME}" -o "${BIN_SHA_NAME}"
fi

backup_file="${RELEASE_DIR}/${BIN_NAME}.bak.$(date +%Y%m%d%H%M%S)"
previous_runtime_hash=""
runtime_backup_archive=""
updated_mode="binary"

if [[ "${has_runtime_package}" == "1" ]]; then
  echo "[update] verifying runtime package checksum..."
  verify_checksum "${RUNTIME_PKG_NAME}" "${RUNTIME_PKG_SHA_NAME}"
  downloaded_runtime_hash="$(calc_sha256 "${RUNTIME_PKG_NAME}")"
  current_runtime_hash=""
  if [[ -f "${RUNTIME_HASH_FILE}" ]]; then
    current_runtime_hash="$(tr -d ' \r\n' < "${RUNTIME_HASH_FILE}")"
  fi
  echo "[update] runtime_local_hash=${current_runtime_hash:-none}"
  echo "[update] runtime_remote_hash=${downloaded_runtime_hash}"
  if [[ -n "${downloaded_runtime_hash}" && -n "${current_runtime_hash}" && "${current_runtime_hash}" == "${downloaded_runtime_hash}" ]]; then
    echo "[update] already latest runtime package, skip replace/restart"
    notify_tg "✅ 当前已经是最新版本\n\n版本: ${LATEST_TAG:-未知}"
    exit 0
  fi

  extract_dir="${TMP_DIR}/runtime"
  mkdir -p "${extract_dir}"
  tar -xzf "${RUNTIME_PKG_NAME}" -C "${extract_dir}"

  if [[ ! -f "${extract_dir}/release/${BIN_NAME}" ]]; then
    echo "[update] runtime package missing release/${BIN_NAME}"
    exit 1
  fi
  if [[ ! -d "${extract_dir}/web" ]]; then
    echo "[update] runtime package missing web directory"
    exit 1
  fi

  if [[ -f "${RELEASE_DIR}/${BIN_NAME}" ]]; then
    cp -f "${RELEASE_DIR}/${BIN_NAME}" "${backup_file}"
  fi
  if [[ -f "${RUNTIME_HASH_FILE}" ]]; then
    previous_runtime_hash="$(tr -d ' \r\n' < "${RUNTIME_HASH_FILE}")"
  fi
  existing_runtime_dirs=()
  if [[ -d "${APP_DIR}/web" ]]; then
    existing_runtime_dirs+=("web")
  fi
  if [[ -d "${APP_DIR}/docs" ]]; then
    existing_runtime_dirs+=("docs")
  fi
  if [[ ${#existing_runtime_dirs[@]} -gt 0 ]]; then
    runtime_backup_archive="${TMP_DIR}/runtime-content-backup.tar.gz"
    tar -czf "${runtime_backup_archive}" -C "${APP_DIR}" "${existing_runtime_dirs[@]}"
  fi

  echo "[update] applying runtime package..."
  install -m 0644 "${extract_dir}/release/${BIN_NAME}" "${RELEASE_DIR}/${BIN_NAME}"
  mkdir -p "${APP_DIR}/web"
  cp -a "${extract_dir}/web/." "${APP_DIR}/web/"
  if [[ -d "${extract_dir}/docs" ]]; then
    mkdir -p "${APP_DIR}/docs"
    cp -a "${extract_dir}/docs/." "${APP_DIR}/docs/"
  fi
  printf "%s\n" "${downloaded_runtime_hash}" > "${RUNTIME_HASH_FILE}"
  updated_mode="runtime"
else
  echo "[update] verifying binary checksum..."
  verify_checksum "${BIN_NAME}" "${BIN_SHA_NAME}"
  downloaded_hash="$(calc_sha256 "${BIN_NAME}")"
  current_hash=""
  if [[ -f "${RELEASE_DIR}/${BIN_NAME}" ]]; then
    current_hash="$(calc_sha256 "${RELEASE_DIR}/${BIN_NAME}")"
  fi
  echo "[update] local_hash=${current_hash:-none}"
  echo "[update] remote_hash=${downloaded_hash}"
  if [[ -n "${downloaded_hash}" && -n "${current_hash}" && "${current_hash}" == "${downloaded_hash}" ]]; then
    echo "[update] already latest binary, skip replace/restart"
    notify_tg "✅ 当前已经是最新版本\n\n版本: ${LATEST_TAG:-未知}"
    exit 0
  fi

  if [[ -f "${RELEASE_DIR}/${BIN_NAME}" ]]; then
    cp -f "${RELEASE_DIR}/${BIN_NAME}" "${backup_file}"
  fi

  echo "[update] replacing binary..."
  install -m 0644 "${BIN_NAME}" "${RELEASE_DIR}/${BIN_NAME}"
fi

echo "[update] restarting pm2 process ${PROCESS_NAME}..."
if pm2 restart "${PROCESS_NAME}" --update-env; then
  sleep 2
  pm2 describe "${PROCESS_NAME}" >/dev/null
  if [[ "${updated_mode}" == "runtime" ]]; then
    notify_tg "✅ 更新完成\n版本: ${LATEST_TAG:-未知}\n状态: 主程序和页面资源已更新并重启"
  else
    notify_tg "✅ 更新完成\n版本: ${LATEST_TAG:-未知}\n状态: 主程序已更新并重启"
  fi
  echo "[update] success"
  exit 0
fi

echo "[update] restart failed, rolling back..."
if [[ -f "${backup_file}" ]]; then
  cp -f "${backup_file}" "${RELEASE_DIR}/${BIN_NAME}"
fi
if [[ "${updated_mode}" == "runtime" ]]; then
  if [[ -n "${runtime_backup_archive}" && -f "${runtime_backup_archive}" ]]; then
    rm -rf "${APP_DIR}/web" "${APP_DIR}/docs"
    tar -xzf "${runtime_backup_archive}" -C "${APP_DIR}" || true
  fi
  if [[ -n "${previous_runtime_hash}" ]]; then
    printf "%s\n" "${previous_runtime_hash}" > "${RUNTIME_HASH_FILE}"
  else
    rm -f "${RUNTIME_HASH_FILE}"
  fi
fi
pm2 restart "${PROCESS_NAME}" --update-env || true
notify_tg "❌ 更新失败\n版本: ${LATEST_TAG:-未知}\n请登录服务器查看日志: ${WORKER_LOG}"
exit 1
