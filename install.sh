#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/tg-antispam"
PROCESS_NAME="tg-buyer"
DEFAULT_REPO_URL="https://github.com/ryty1/tg-antispam.git"
NODE_MAJOR_REQUIRED=22

DEFAULT_LICENSE_CHECK_TIMEOUT_MS="8000"
DEFAULT_LICENSE_OFFLINE_GRACE_HOURS="24"
DEFAULT_WEB_PORT="8787"
DEFAULT_WEBHOOK_WORKERS="15"
DEFAULT_WEBHOOK_QUEUE_MAX="10000"
DEFAULT_SESSION_QUEUE_MAX_PER_KEY="400"
DEFAULT_SESSION_QUEUE_MAX_GLOBAL="6000"
DEFAULT_UPDATE_APPLY_TIMEOUT_SECONDS="600"

DEFAULT_AI_POOL_1="https://cliapi.ioa.de5.net/v1|sk-I70u88srB28mdiaua|gpt-5.4-mini|chat"
DEFAULT_AI_POOL_2="https://cli.axxhy.pp.ua/v1|sk-9IbqFj3YUq1Exw315|gpt-5.4-mini|chat"
DEFAULT_AI_POOL_3="https://api.dabo.im|sk-qsfn4BdbXeWZJjAIszyLGdAlfaBvC1c0jDmZoeyXalbsjpzF|grok-3-thinking"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

log() {
  printf "[install] %s\n" "$*"
}

die() {
  printf "[install] ERROR: %s\n" "$*" >&2
  exit 1
}

run_privileged() {
  if [[ -n "${SUDO}" ]]; then
    ${SUDO} "$@"
  else
    "$@"
  fi
}

ensure_apt_available() {
  command -v apt-get >/dev/null 2>&1 || die "当前脚本仅支持 Debian/Ubuntu（apt-get）"
}

ensure_base_tools() {
  ensure_apt_available
  if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    log "安装基础依赖（curl/git）..."
    run_privileged apt-get update -y
    run_privileged apt-get install -y curl git
  fi
}

ensure_nodejs() {
  local install_required="1"
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ -n "${major}" ]] && [[ "${major}" -ge "${NODE_MAJOR_REQUIRED}" ]]; then
      install_required="0"
    fi
  fi

  if [[ "${install_required}" == "0" ]]; then
    log "Node.js 已满足要求: $(node -v)"
    return
  fi

  log "安装 Node.js ${NODE_MAJOR_REQUIRED}.x ..."
  if [[ -n "${SUDO}" ]]; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x" | sudo -E bash -
  else
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_REQUIRED}.x" | bash -
  fi
  run_privileged apt-get install -y nodejs
  log "Node.js 安装完成: $(node -v)"
}

ensure_pm2() {
  if command -v pm2 >/dev/null 2>&1; then
    log "PM2 已安装: $(pm2 -v)"
    return
  fi
  log "安装 PM2 ..."
  run_privileged npm install -g pm2
  log "PM2 安装完成"
}

clone_or_update_repo() {
  local repo_url="${1:-${DEFAULT_REPO_URL}}"
  if [[ -d "${APP_DIR}/.git" ]]; then
    log "检测到已有仓库，执行更新"
    git -C "${APP_DIR}" pull --ff-only
    return
  fi

  if [[ -e "${APP_DIR}" ]] && [[ -n "$(ls -A "${APP_DIR}" 2>/dev/null || true)" ]]; then
    die "${APP_DIR} 已存在且非空，但不是 git 仓库，请先清理后重试"
  fi

  run_privileged mkdir -p "${APP_DIR}"
  run_privileged chown "$(id -u):$(id -g)" "${APP_DIR}"
  log "克隆仓库: ${repo_url}"
  git clone "${repo_url}" "${APP_DIR}"
}

install_dependencies() {
  log "安装运行依赖..."
  npm --prefix "${APP_DIR}" install --omit=dev
}

read_existing_env_value() {
  local key="$1"
  local env_file="${APP_DIR}/.env"
  if [[ ! -f "${env_file}" ]]; then
    printf ""
    return
  fi
  local line
  line="$(grep -E "^${key}=" "${env_file}" | tail -n 1 || true)"
  printf "%s" "${line#*=}"
}

prompt_value() {
  local prompt_text="$1"
  local default_value="$2"
  local input=""
  read -r -p "${prompt_text} [${default_value}]: " input || true
  if [[ -z "${input}" ]]; then
    printf "%s" "${default_value}"
  else
    printf "%s" "${input}"
  fi
}

normalize_base_url() {
  local raw="$1"
  raw="${raw%/}"
  printf "%s" "${raw}"
}

generate_random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
    return
  fi
  od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
}

configure_env_interactive() {
  local env_file="${APP_DIR}/.env"
  local existing_bot_token
  local existing_admin_user_id
  local existing_license_server_url
  local existing_license_key
  local existing_web_base_url
  local existing_github_token

  existing_bot_token="$(read_existing_env_value BOT_TOKEN)"
  existing_admin_user_id="$(read_existing_env_value ADMIN_USER_ID)"
  existing_license_server_url="$(read_existing_env_value LICENSE_SERVER_URL)"
  existing_license_key="$(read_existing_env_value LICENSE_KEY)"
  existing_web_base_url="$(read_existing_env_value WEB_BASE_URL)"
  existing_github_token="$(read_existing_env_value UPDATE_GITHUB_TOKEN)"

  local bot_token
  local admin_user_id
  local license_server_url
  local license_key
  local web_base_url
  local github_token
  local webhook_secret
  local webhook_path
  local webhook_url

  log "开始在线配置 .env（只问必要项）"
  bot_token="$(prompt_value "请输入机器人 BOT_TOKEN（在 @BotFather 获取）" "${existing_bot_token}")"
  admin_user_id="$(prompt_value "请输入管理员 Telegram Chat ID（数字）" "${existing_admin_user_id}")"
  license_server_url="$(prompt_value "请输入授权服务器地址（例如 https://license.example.com）" "${existing_license_server_url}")"
  license_key="$(prompt_value "请输入授权码 LICENSE_KEY" "${existing_license_key}")"
  web_base_url="$(prompt_value "请输入后台域名 WEB_BASE_URL（例如 https://bot.example.com）" "${existing_web_base_url}")"
  github_token="$(prompt_value "可选：GitHub Token（避免 API 限流，回车跳过）" "${existing_github_token}")"

  [[ -n "${bot_token}" ]] || die "BOT_TOKEN 不能为空"
  [[ -n "${admin_user_id}" ]] || die "ADMIN_USER_ID 不能为空"
  [[ -n "${license_server_url}" ]] || die "LICENSE_SERVER_URL 不能为空"
  [[ -n "${license_key}" ]] || die "LICENSE_KEY 不能为空"
  [[ -n "${web_base_url}" ]] || die "WEB_BASE_URL 不能为空"

  web_base_url="$(normalize_base_url "${web_base_url}")"
  if [[ ! "${web_base_url}" =~ ^https?:// ]]; then
    die "WEB_BASE_URL 必须以 http:// 或 https:// 开头"
  fi

  webhook_secret="$(generate_random_token)"
  webhook_path="$(generate_random_token)"
  webhook_url="${web_base_url}/api/telegram/webhook/${webhook_path}"

  cat >"${env_file}" <<EOF
BOT_TOKEN=${bot_token}
ADMIN_USER_ID=${admin_user_id}

LICENSE_SERVER_URL=${license_server_url}
LICENSE_KEY=${license_key}
LICENSE_CHECK_TIMEOUT_MS=${DEFAULT_LICENSE_CHECK_TIMEOUT_MS}
LICENSE_OFFLINE_GRACE_HOURS=${DEFAULT_LICENSE_OFFLINE_GRACE_HOURS}

WEB_BASE_URL=${web_base_url}
WEB_PORT=${DEFAULT_WEB_PORT}
WEBHOOK_URL=${webhook_url}
WEBHOOK_SECRET=${webhook_secret}

AI_POOL_1=${DEFAULT_AI_POOL_1}
AI_POOL_2=${DEFAULT_AI_POOL_2}
AI_POOL_3=${DEFAULT_AI_POOL_3}

WEBHOOK_WORKERS=${DEFAULT_WEBHOOK_WORKERS}
WEBHOOK_QUEUE_MAX=${DEFAULT_WEBHOOK_QUEUE_MAX}
SESSION_QUEUE_MAX_PER_KEY=${DEFAULT_SESSION_QUEUE_MAX_PER_KEY}
SESSION_QUEUE_MAX_GLOBAL=${DEFAULT_SESSION_QUEUE_MAX_GLOBAL}

UPDATE_APPLY_TIMEOUT_SECONDS=${DEFAULT_UPDATE_APPLY_TIMEOUT_SECONDS}
EOF

  if [[ -n "${github_token}" ]]; then
    {
      printf "UPDATE_GITHUB_TOKEN=%s\n" "${github_token}"
      printf "GITHUB_TOKEN=%s\n" "${github_token}"
    } >>"${env_file}"
  fi

  log ".env 生成完成: ${env_file}"
  log "已自动生成 WEBHOOK_URL 与 WEBHOOK_SECRET"
}

ensure_update_script_ready() {
  local update_script="${APP_DIR}/update-buyer.sh"
  [[ -f "${update_script}" ]] || die "缺少更新脚本: ${update_script}"
  chmod +x "${update_script}"
  log "已设置更新脚本执行权限: ${update_script}"
}

pm2_start_or_restart() {
  local target="${APP_DIR}/release/app.protected.buyer.cjs"
  [[ -f "${target}" ]] || die "缺少运行文件: ${target}"

  if pm2 describe "${PROCESS_NAME}" >/dev/null 2>&1; then
    log "重启 PM2 进程: ${PROCESS_NAME}"
    pm2 restart "${PROCESS_NAME}" --update-env
  else
    log "启动 PM2 进程: ${PROCESS_NAME}"
    pm2 start "${target}" --name "${PROCESS_NAME}"
  fi

  pm2 save
  pm2 startup systemd -u "$(whoami)" --hp "${HOME}" >/tmp/pm2-startup.out 2>&1 || true
  log "PM2 已运行，查看日志: pm2 logs ${PROCESS_NAME}"
}

pm2_stop_and_delete() {
  if pm2 describe "${PROCESS_NAME}" >/dev/null 2>&1; then
    pm2 stop "${PROCESS_NAME}" || true
    pm2 delete "${PROCESS_NAME}" || true
    pm2 save || true
  fi
}

cmd_install() {
  local repo_url="${1:-${DEFAULT_REPO_URL}}"
  ensure_base_tools
  ensure_nodejs
  ensure_pm2
  clone_or_update_repo "${repo_url}"
  install_dependencies
  configure_env_interactive
  ensure_update_script_ready
  pm2_start_or_restart
  log "安装完成"
}

cmd_env() {
  [[ -d "${APP_DIR}" ]] || die "目录不存在: ${APP_DIR}，请先执行 install"
  configure_env_interactive
  log "如需生效请执行: $0 restart"
}

cmd_start() {
  ensure_update_script_ready
  pm2_start_or_restart
}

cmd_restart() {
  if pm2 describe "${PROCESS_NAME}" >/dev/null 2>&1; then
    pm2 restart "${PROCESS_NAME}" --update-env
    pm2 save || true
    log "重启完成"
    return
  fi
  cmd_start
}

cmd_stop() {
  pm2_stop_and_delete
  log "已停止"
}

cmd_logs() {
  pm2 logs "${PROCESS_NAME}"
}

cmd_status() {
  pm2 status "${PROCESS_NAME}"
}

cmd_update_now() {
  local update_script="${APP_DIR}/update-buyer.sh"
  [[ -x "${update_script}" ]] || die "更新脚本不存在或不可执行: ${update_script}"
  "${update_script}"
}

cmd_uninstall() {
  pm2_stop_and_delete
  read -r -p "是否删除 ${APP_DIR} 目录? [y/N]: " answer || true
  case "${answer}" in
    y|Y|yes|YES)
      run_privileged rm -rf "${APP_DIR}"
      log "已删除 ${APP_DIR}"
      ;;
    *)
      log "保留目录: ${APP_DIR}"
      ;;
  esac
  log "卸载完成"
}

show_help() {
  cat <<'EOF'
买家一键部署脚本

用法:
  bash install.sh                    打开交互菜单（默认）
  bash install.sh menu               打开交互菜单
  bash install.sh install [repo_url]   一键安装（克隆/依赖/.env/pm2）
  bash install.sh env                  在线重配 .env
  bash install.sh start                启动 PM2
  bash install.sh restart              重启 PM2
  bash install.sh stop                 停止并移除 PM2 进程
  bash install.sh logs                 查看日志
  bash install.sh status               查看状态
  bash install.sh update-now           立即执行更新脚本
  bash install.sh uninstall            卸载（可选删除 /opt/tg-antispam）
EOF
}

pause_for_enter() {
  read -r -p "按回车继续..." _ || true
}

run_menu_action() {
  local label="$1"
  shift
  if ("$@"); then
    log "${label}：完成"
  else
    log "${label}：失败，请按日志排查后重试"
  fi
}

cmd_menu() {
  if [[ ! -t 0 ]]; then
    show_help
    return
  fi

  while true; do
    printf "\n==== TG 买家部署菜单 ====\n"
    printf "1) 一键安装（克隆/依赖/.env/PM2）\n"
    printf "2) 重配 .env\n"
    printf "3) 启动服务\n"
    printf "4) 重启服务\n"
    printf "5) 停止服务\n"
    printf "6) 查看日志\n"
    printf "7) 查看状态\n"
    printf "8) 立即更新\n"
    printf "9) 卸载\n"
    printf "0) 退出\n"

    local choice=""
    read -r -p "请输入序号 [0-9]: " choice || true

    case "${choice}" in
      1)
        local repo_url=""
        read -r -p "仓库地址（回车用默认 ${DEFAULT_REPO_URL}）: " repo_url || true
        repo_url="${repo_url:-${DEFAULT_REPO_URL}}"
        run_menu_action "一键安装" cmd_install "${repo_url}"
        pause_for_enter
        ;;
      2)
        run_menu_action "重配 .env" cmd_env
        pause_for_enter
        ;;
      3)
        run_menu_action "启动服务" cmd_start
        pause_for_enter
        ;;
      4)
        run_menu_action "重启服务" cmd_restart
        pause_for_enter
        ;;
      5)
        run_menu_action "停止服务" cmd_stop
        pause_for_enter
        ;;
      6)
        cmd_logs
        ;;
      7)
        run_menu_action "查看状态" cmd_status
        pause_for_enter
        ;;
      8)
        run_menu_action "立即更新" cmd_update_now
        pause_for_enter
        ;;
      9)
        run_menu_action "卸载" cmd_uninstall
        pause_for_enter
        ;;
      0|q|Q|quit|exit)
        log "已退出"
        break
        ;;
      *)
        log "无效序号，请输入 0-9"
        ;;
    esac
  done
}

main() {
  local cmd="${1:-menu}"
  shift || true
  case "${cmd}" in
    menu) cmd_menu ;;
    install) cmd_install "$@" ;;
    env) cmd_env ;;
    start) cmd_start ;;
    restart) cmd_restart ;;
    stop) cmd_stop ;;
    logs) cmd_logs ;;
    status) cmd_status ;;
    update-now) cmd_update_now ;;
    uninstall) cmd_uninstall ;;
    help|-h|--help) show_help ;;
    *)
      show_help
      exit 1
      ;;
  esac
}

main "$@"
