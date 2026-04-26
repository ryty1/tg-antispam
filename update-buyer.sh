#!/usr/bin/env bash
set -euo pipefail

REPO="ryty1/tg-antispam"
APP_DIR="/opt/tg-antispam"
RELEASE_DIR="${APP_DIR}/release"
PROCESS_NAME="tg-buyer"
BIN_NAME="app.protected.buyer.cjs"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
LOCK_FILE="/tmp/tg-buyer-update.lock"
TMP_DIR="$(mktemp -d)"

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
  echo "[update] success"
  exit 0
fi

echo "[update] restart failed, rolling back..."
if [[ -f "${backup_file}" ]]; then
  cp -f "${backup_file}" "${RELEASE_DIR}/${BIN_NAME}"
  pm2 restart "${PROCESS_NAME}" --update-env || true
fi
exit 1
