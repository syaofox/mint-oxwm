#!/bin/bash
# Linux Mint 22.3 OXWM 安装脚本
# 基于 docs/计划.md 自动化安装流程
# 以普通用户运行，仅在需要的地方使用 sudo
# 使用 whiptail 交互式菜单，支持分步执行和失败重试

set -uo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}==> $1${NC}"; }

# 检查不应以 root 运行
[[ "$EUID" -eq 0 ]] && { echo -e "${RED}请勿使用 root 运行此脚本${NC}"; exit 1; }

# 检查 whiptail
command -v whiptail &>/dev/null || { echo -e "${RED}未安装 whiptail，请运行: sudo apt install whiptail${NC}"; exit 1; }

# 获取当前用户
REAL_USER="$(whoami)"
USER_HOME="$HOME"

# 获取脚本所在目录（即项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# 步骤状态追踪
declare -A STEP_STATUS
for i in {1..7}; do STEP_STATUS[$i]="pending"; done

# ============================================================
# 步骤函数定义
# ============================================================

step_deps() {
    log_step "1/7 安装系统依赖..."
    if sudo apt update -y 2>&1 | tail -5; then
        if sudo apt install -y \
            build-essential python3-dev \
            git \
            libx11-dev libxft-dev libxinerama-dev libxrandr-dev \
            libxcursor-dev libxcomposite-dev libxdamage-dev \
            liblua5.4-dev \
            rofi maim xclip xsel xwallpaper dunst pasystray picom \
            wireplumber xfce4-clipman xdotool ffmpeg imagemagick \
            zenity x11-xserver-utils catfish vim lxappearance \
            fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 \
            fcitx5-frontend-gtk4 fcitx5-frontend-qt5 fcitx5-material-color \
            gnome-keyring policykit-1-gnome wget curl xz-utils \
            whiptail file rsync 2>&1 | tail -5; then
            log_info "系统依赖安装完成"
            return 0
        fi
    fi
    log_error "系统依赖安装失败"
    return 1
}

step_zig() {
    log_step "2/7 安装 Zig 编译器..."

    local ZIG_VERSION="0.15.2"
    local ZIG_ARCH

    case "$(uname -m)" in
        x86_64)  ZIG_ARCH="x86_64" ;;
        aarch64) ZIG_ARCH="aarch64" ;;
        armv7l)  ZIG_ARCH="arm" ;;
        *)       log_error "不支持的架构: $(uname -m)"; return 1 ;;
    esac

    local ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz"
    local ZIG_DIR="/opt/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}"

    if [[ -f "$ZIG_DIR/zig" ]]; then
        log_warn "Zig ${ZIG_VERSION} 已安装，跳过"
        return 0
    fi

    log_info "下载 Zig ${ZIG_VERSION} (${ZIG_ARCH})..."
    if ! wget -q "$ZIG_URL" -O /tmp/zig.tar.xz; then
        log_error "Zig 下载失败"
        return 1
    fi

    log_info "解压到 /opt/..."
    if ! sudo tar -xf /tmp/zig.tar.xz -C /opt/; then
        log_error "Zig 解压失败"
        rm -f /tmp/zig.tar.xz
        return 1
    fi
    sudo rm -f /tmp/zig.tar.xz
    sudo ln -sf "$ZIG_DIR/zig" /usr/local/bin/zig

    log_info "Zig 安装完成: $(zig version)"
    return 0
}

step_font() {
    log_step "3/7 安装 JetBrains Mono Nerd Font..."

    local NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.tar.xz"
    local FONT_DIR="$USER_HOME/.local/share/fonts"

    mkdir -p "$FONT_DIR"

    if ls "$FONT_DIR"/JetBrainsMono*.ttf 1>/dev/null 2>&1; then
        log_warn "JetBrains Mono Nerd Font 已安装，跳过"
        return 0
    fi

    log_info "下载 JetBrains Mono Nerd Font..."
    if ! wget -q "$NERD_FONT_URL" -O /tmp/JetBrainsMono.tar.xz; then
        log_error "字体下载失败"
        return 1
    fi

    log_info "解压字体..."
    if ! tar -xf /tmp/JetBrainsMono.tar.xz -C "$FONT_DIR"; then
        log_error "字体解压失败"
        rm -f /tmp/JetBrainsMono.tar.xz
        return 1
    fi
    rm -f /tmp/JetBrainsMono.tar.xz

    log_info "刷新字体缓存..."
    fc-cache -f "$FONT_DIR"
    log_info "Nerd Font 安装完成"
    return 0
}

step_oxwm() {
    log_step "4/7 编译安装 OXWM..."

    local OXWM_REPO="git@github.com:syaofox/oxwm.git"
    local OXWM_SRC="/tmp/oxwm"

    if [[ -d "$OXWM_SRC/.git" ]]; then
        log_warn "OXWM 源码已存在，执行 git pull..."
        if ! git -C "$OXWM_SRC" pull; then
            log_error "OXWM git pull 失败"
            return 1
        fi
    else
        log_info "克隆 OXWM 仓库..."
        if ! git clone "$OXWM_REPO" "$OXWM_SRC"; then
            log_error "OXWM 克隆失败"
            return 1
        fi
    fi

    cd "$OXWM_SRC" || { log_error "无法进入 $OXWM_SRC"; return 1; }

    log_info "构建 OXWM (ReleaseSmall)..."
    if ! zig build -Doptimize=ReleaseSmall; then
        log_error "OXWM 构建失败"
        return 1
    fi

    log_info "安装 OXWM 到 /usr..."
    if ! sudo zig build -Doptimize=ReleaseSmall --prefix /usr install; then
        log_error "OXWM 安装失败"
        return 1
    fi

    log_info "OXWM 安装完成"
    return 0
}

step_dotfiles() {
    log_step "5/7 部署配置文件..."

    # --- Nemo actions & scripts ---
    local NEMO_ACTIONS_DIR="$USER_HOME/.local/share/nemo/actions"
    local NEMO_SCRIPTS_DIR="$USER_HOME/.local/share/nemo/scripts"

    mkdir -p "$NEMO_ACTIONS_DIR" "$NEMO_SCRIPTS_DIR"

    log_info "复制 Nemo actions..."
    cp -f "$PROJECT_DIR"/dotfiles/nemo/actions/*.nemo_action "$NEMO_ACTIONS_DIR/" || { log_error "Nemo actions 复制失败"; return 1; }

    log_info "复制 Nemo scripts..."
    cp -f "$PROJECT_DIR"/dotfiles/nemo/scripts/*.sh "$NEMO_SCRIPTS_DIR/" || { log_error "Nemo scripts 复制失败"; return 1; }
    chmod +x "$NEMO_SCRIPTS_DIR"/*.sh

    # --- OXWM 配置 ---
    local OXWM_CONFIG_DIR="$USER_HOME/.config/oxwm"
    mkdir -p "$OXWM_CONFIG_DIR"

    log_info "复制 OXWM 配置..."
    cp -f "$PROJECT_DIR"/dotfiles/oxwm/config.lua "$OXWM_CONFIG_DIR/" || { log_error "OXWM 配置复制失败"; return 1; }

    # 填充 oxwm-start.sh 中的路径占位符
    local OXWM_START_SRC="$PROJECT_DIR/dotfiles/oxwm/oxwm-start.sh"
    local OXWM_START_DST="$OXWM_CONFIG_DIR/oxwm-start.sh"

    log_info "生成 oxwm-start.sh..."
    cp -f "$OXWM_START_SRC" "$OXWM_START_DST" || { log_error "oxwm-start.sh 生成失败"; return 1; }
    chmod +x "$OXWM_START_DST"

    # --- 其他 dotfiles ---
    log_info "复制 dunstrc..."
    mkdir -p "$USER_HOME/.config/dunst"
    cp -f "$PROJECT_DIR"/dotfiles/dunstrc "$USER_HOME/.config/dunst/dunstrc" || { log_error "dunstrc 复制失败"; return 1; }

    log_info "复制 picom.conf..."
    mkdir -p "$USER_HOME/.config/picom"
    cp -f "$PROJECT_DIR"/dotfiles/picom.conf "$USER_HOME/.config/picom/picom.conf" || { log_error "picom.conf 复制失败"; return 1; }

    log_info "复制 rofi 主题..."
    mkdir -p "$USER_HOME/.config/rofi"
    cp -f "$PROJECT_DIR"/dotfiles/rofi/theme.rasi "$USER_HOME/.config/rofi/theme.rasi" || { log_error "rofi 主题复制失败"; return 1; }

    log_info "配置文件部署完成"
    return 0
}

step_desktop() {
    log_step "6/7 创建 LightDM 会话入口..."

    local DESKTOP_FILE="/usr/share/xsessions/oxwm.desktop"
    local OXWM_START_DST="$USER_HOME/.config/oxwm/oxwm-start.sh"

    if sudo tee "$DESKTOP_FILE" > /dev/null <<EOF; then
[Desktop Entry]
Encoding=UTF-8
Name=oxwm
Comment=Dynamic window manager written in Zig
Exec=$OXWM_START_DST
Icon=oxwm
Type=XSession
EOF
        sudo chmod 644 "$DESKTOP_FILE"
        log_info "会话入口已创建: $DESKTOP_FILE"
        return 0
    fi
    log_error "会话入口创建失败"
    return 1
}

step_wallpaper() {
    log_step "7/7 设置壁纸..."

    local WALLPAPER_DIR="$USER_HOME/Pictures/wallpapers"
    mkdir -p "$WALLPAPER_DIR"

    local count=0
    for wallpaper in "$PROJECT_DIR"/walls/*; do
        if [[ -f "$wallpaper" ]]; then
            if cp -f "$wallpaper" "$WALLPAPER_DIR/"; then
                log_info "复制壁纸: $(basename "$wallpaper")"
                ((count++))
            else
                log_error "壁纸复制失败: $(basename "$wallpaper")"
                return 1
            fi
        fi
    done

    log_info "壁纸已复制到: $WALLPAPER_DIR ($count 个文件)"
    return 0
}

# 步骤元数据
STEP_NAMES=(
    "1. 安装系统依赖"
    "2. 安装 Zig 编译器"
    "3. 安装 Nerd Font"
    "4. 编译安装 OXWM"
    "5. 部署配置文件"
    "6. 创建 LightDM 会话"
    "7. 设置壁纸"
)

STEP_FUNCS=(
    step_deps
    step_zig
    step_font
    step_oxwm
    step_dotfiles
    step_desktop
    step_wallpaper
)

# ============================================================
# 主流程：顺序执行，失败则停止
# ============================================================

for i in {0..6}; do
    step_num=$((i + 1))

    # 显示当前步骤
    whiptail --infobox "正在执行: ${STEP_NAMES[$i]}..." 5 50

    if ${STEP_FUNCS[$i]}; then
        STEP_STATUS[$step_num]="done"
        whiptail --msgbox --title "成功" "${STEP_NAMES[$i]} 完成" 8 50
    else
        STEP_STATUS[$step_num]="fail"
        if whiptail --yesno --title "失败" "${STEP_NAMES[$i]} 执行失败！\n\n是否重试？\n(取消 = 退出安装)" 10 50; then
            ((i--))
            continue
        else
            exit 1
        fi
    fi

    # 全部完成
    if [[ $step_num -eq 7 ]]; then
        whiptail --msgbox --title "安装完成" \
            "所有步骤已完成！\n\n请重启系统或重新登录，\n然后在 LightDM 界面选择 'oxwm' 会话。\n\n配置文件位置:\n  OXWM:  ~/.config/oxwm/\n  Dunst: ~/.config/dunst/dunstrc\n  Picom: ~/.config/picom/picom.conf\n  Rofi:  ~/.config/rofi/theme.rasi\n  Nemo:  ~/.local/share/nemo/actions/" \
            18 60
        exit 0
    fi
done
