#!/bin/bash
# 常用软件安装脚本 - 交互式多选
# 优先使用各软件官方源安装

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}==> $1${NC}"; }

[[ "$EUID" -eq 0 ]] && { echo -e "${RED}请勿使用 root 运行此脚本${NC}"; exit 1; }

# ============================================================
# 交互式多选菜单
# ============================================================
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}     常用软件安装 (空格选择, 回车确认)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

OPTIONS=(
    "brave"    "Brave Browser (官方源)"
    "chrome"   "Google Chrome (官方源)"
    "vscode"   "VS Code Microsoft (官方源)"
    "docker"   "Docker + Compose + NVIDIA GPU 支持 (官方源)"
)

SELECTED=()

# 构建 whiptail 菜单参数
MENU_ITEMS=()
for i in "${!OPTIONS[@]}"; do
    if (( i % 2 == 0 )); then
        MENU_ITEMS+=("${OPTIONS[$i]}" "${OPTIONS[$i+1]}" "off")
    fi
done

# 使用 whiptail 显示多选菜单
CHOICES=$(whiptail --title "选择要安装的软件" --checklist \
    "使用空格键选择/取消, Tab 切换按钮, 回车确认" \
    15 60 4 \
    "${MENU_ITEMS[@]}" \
    3>&1 1>&2 2>&3) || exit 1

# 解析选择结果
for choice in $CHOICES; do
    SELECTED+=("$(echo "$choice" | tr -d '"')")
done

if [[ ${#SELECTED[@]} -eq 0 ]]; then
    log_warn "未选择任何软件, 退出"
    exit 0
fi

log_info "已选择: ${SELECTED[*]}"

# ============================================================
# 安装 Brave Browser
# ============================================================
install_brave() {
    log_step "安装 Brave Browser..."

    if command -v brave-browser &>/dev/null; then
        log_warn "Brave Browser 已安装, 跳过"
        return
    fi

    sudo apt install -y curl gpg
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg

    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
        sudo tee /etc/apt/sources.list.d/brave-browser-release.list

    sudo apt update
    sudo apt install -y brave-browser
    log_info "Brave Browser 安装完成"
}

# ============================================================
# 安装 Google Chrome
# ============================================================
install_chrome() {
    log_step "安装 Google Chrome..."

    if command -v google-chrome &>/dev/null; then
        log_warn "Google Chrome 已安装, 跳过"
        return
    fi

    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)       log_error "不支持的架构: $(uname -m)"; return ;;
    esac

    wget -q -O /tmp/google-chrome.deb \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_${arch}.deb"
    sudo apt install -y /tmp/google-chrome.deb
    rm -f /tmp/google-chrome.deb
    log_info "Google Chrome 安装完成"
}

# ============================================================
# 安装 VS Code
# ============================================================
install_vscode() {
    log_step "安装 VS Code (Microsoft)..."

    if command -v code &>/dev/null; then
        log_warn "VS Code 已安装, 跳过"
        return
    fi

    sudo apt install -y wget gpg apt-transport-https
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor > /tmp/packages.microsoft.gpg
    sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg \
        /etc/apt/keyrings/packages.microsoft.gpg
    rm -f /tmp/packages.microsoft.gpg

    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
        sudo tee /etc/apt/sources.list.d/vscode.list

    sudo apt update
    sudo apt install -y code
    log_info "VS Code 安装完成"
}

# ============================================================
# 安装 Docker + Compose + NVIDIA GPU 支持
# ============================================================
install_docker() {
    log_step "安装 Docker + Docker Compose + NVIDIA GPU 支持..."

    if command -v docker &>/dev/null; then
        log_warn "Docker 已安装, 跳过"
        return
    fi

    # 卸载旧版本
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt remove -y "$pkg" 2>/dev/null || true
    done

    # 添加 Docker 官方 GPG 密钥
    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # 添加 Docker 官方源 (DEB822 格式)
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 添加当前用户到 docker 组
    sudo usermod -aG docker "$USER"
    log_info "Docker 安装完成 (需重新登录生效 docker 组权限)"

    # NVIDIA Container Toolkit (GPU 支持)
    if command -v nvidia-smi &>/dev/null; then
        log_info "检测到 NVIDIA 驱动, 安装 NVIDIA Container Toolkit..."

        if command -v nvidia-container-cli &>/dev/null; then
            log_warn "NVIDIA Container Toolkit 已安装, 跳过"
        else
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

            sudo apt update
            sudo apt install -y nvidia-container-toolkit
            sudo nvidia-ctk runtime configure --runtime=docker
            sudo systemctl restart docker
            log_info "NVIDIA Container Toolkit 安装完成"
        fi
    else
        log_warn "未检测到 NVIDIA 驱动, 跳过 GPU 支持安装"
    fi

    log_info "Docker + Compose + GPU 支持安装完成"
}

# ============================================================
# 执行安装
# ============================================================
for app in "${SELECTED[@]}"; do
    case "$app" in
        brave)  install_brave ;;
        chrome) install_chrome ;;
        vscode) install_vscode ;;
        docker) install_docker ;;
        *)      log_warn "未知选项: $app" ;;
    esac
done

log_step "安装完成!"
echo ""
log_info "提示: 如果安装了 Docker, 需要重启以使 docker 组权限生效"
