#!/bin/bash
# Linux Mint 22.3 OXWM 安装脚本
# 基于 docs/计划.md 自动化安装流程
# 以普通用户运行，仅在需要的地方使用 sudo
# 修正了原计划中的问题：
#   - zig build 不应使用 sudo（仅 install 需要）
#   - 合并了重复的依赖包列表
#   - 补充了 Nerd Font 自动安装
#   - 自动填充 .desktop 和 oxwm-start.sh 中的路径占位符

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step()  { echo -e "\n${CYAN}==> $1${NC}"; }

# 检查不应以 root 运行
[[ "$EUID" -eq 0 ]] && log_error "请勿使用 root 运行此脚本，以普通用户身份运行即可"

# 获取当前用户
REAL_USER="$(whoami)"
USER_HOME="$HOME"

# 获取脚本所在目录（即项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info "项目目录: $PROJECT_DIR"
log_info "当前用户: $REAL_USER ($USER_HOME)"

# ============================================================
# 1. 安装系统依赖
# ============================================================
log_step "1/7 安装系统依赖..."

sudo apt update -y

sudo apt install -y \
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
    whiptail file rsync

log_info "系统依赖安装完成"

# ============================================================
# 2. 安装 Zig 编译器
# ============================================================
log_step "2/7 安装 Zig 编译器..."

ZIG_VERSION="0.15.2"
ZIG_ARCH="x86_64"

# 检测架构
case "$(uname -m)" in
    x86_64)  ZIG_ARCH="x86_64" ;;
    aarch64) ZIG_ARCH="aarch64" ;;
    armv7l)  ZIG_ARCH="arm" ;;
    *)       log_error "不支持的架构: $(uname -m)" ;;
esac

ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz"
ZIG_DIR="/opt/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}"

if [[ -f "$ZIG_DIR/zig" ]]; then
    log_warn "Zig ${ZIG_VERSION} 已安装，跳过"
else
    log_info "下载 Zig ${ZIG_VERSION} (${ZIG_ARCH})..."
    wget -q "$ZIG_URL" -O /tmp/zig.tar.xz
    log_info "解压到 /opt/..."
    sudo tar -xf /tmp/zig.tar.xz -C /opt/
    sudo rm -f /tmp/zig.tar.xz
    sudo ln -sf "$ZIG_DIR/zig" /usr/local/bin/zig
fi

zig version
log_info "Zig 安装完成: $(zig version)"

# ============================================================
# 3. 安装 JetBrains Mono Nerd Font
# ============================================================
log_step "3/7 安装 JetBrains Mono Nerd Font..."

NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.tar.xz"
FONT_DIR="$USER_HOME/.local/share/fonts"

mkdir -p "$FONT_DIR"

if ls "$FONT_DIR"/JetBrainsMono*.ttf 1>/dev/null 2>&1; then
    log_warn "JetBrains Mono Nerd Font 已安装，跳过"
else
    log_info "下载 JetBrains Mono Nerd Font..."
    wget -q "$NERD_FONT_URL" -O /tmp/JetBrainsMono.tar.xz
    log_info "解压字体..."
    tar -xf /tmp/JetBrainsMono.tar.xz -C "$FONT_DIR"
    rm -f /tmp/JetBrainsMono.tar.xz
fi

log_info "刷新字体缓存..."
fc-cache -f "$FONT_DIR"
log_info "Nerd Font 安装完成"

# ============================================================
# 4. 克隆并编译 OXWM
# ============================================================
log_step "4/7 编译安装 OXWM..."

OXWM_REPO="git@github.com:syaofox/oxwm.git"
OXWM_SRC="/tmp/oxwm"

if [[ -d "$OXWM_SRC/.git" ]]; then
    log_warn "OXWM 源码已存在，执行 git pull..."
    git -C "$OXWM_SRC" pull
else
    log_info "克隆 OXWM 仓库..."
    git clone "$OXWM_REPO" "$OXWM_SRC"
fi

cd "$OXWM_SRC"
log_info "构建 OXWM (ReleaseSmall)..."
zig build -Doptimize=ReleaseSmall --prefix /usr
log_info "安装 OXWM 到 /usr..."
sudo zig build -Doptimize=ReleaseSmall --prefix /usr install
log_info "OXWM 安装完成"

# ============================================================
# 5. 部署配置文件
# ============================================================
log_step "5/7 部署配置文件..."

# --- Nemo actions & scripts ---
NEMO_ACTIONS_DIR="$USER_HOME/.local/share/nemo/actions"
NEMO_SCRIPTS_DIR="$USER_HOME/.local/share/nemo/scripts"

mkdir -p "$NEMO_ACTIONS_DIR" "$NEMO_SCRIPTS_DIR"

log_info "复制 Nemo actions..."
cp -f "$PROJECT_DIR"/dotfiles/nemo/actions/*.nemo_action "$NEMO_ACTIONS_DIR/"

log_info "复制 Nemo scripts..."
cp -f "$PROJECT_DIR"/dotfiles/nemo/scripts/*.sh "$NEMO_SCRIPTS_DIR/"
chmod +x "$NEMO_SCRIPTS_DIR"/*.sh

# --- OXWM 配置 ---
OXWM_CONFIG_DIR="$USER_HOME/.config/oxwm"
mkdir -p "$OXWM_CONFIG_DIR"

log_info "复制 OXWM 配置..."
cp -f "$PROJECT_DIR"/dotfiles/oxwm/config.lua "$OXWM_CONFIG_DIR/"

# 填充 oxwm-start.sh 中的路径占位符
OXWM_START_SRC="$PROJECT_DIR/dotfiles/oxwm/oxwm-start.sh"
OXWM_START_DST="$OXWM_CONFIG_DIR/oxwm-start.sh"

log_info "生成 oxwm-start.sh (填充路径占位符)..."
sed -e "s|DUNSTRC_PATH=XXX|DUNSTRC_PATH=$PROJECT_DIR/dotfiles/dunstrc|" \
    -e "s|PICOM_PATH=xxx|PICOM_PATH=$PROJECT_DIR/dotfiles/picom.conf|" \
    -e "s|WALLPAPER=xxx|WALLPAPER=$PROJECT_DIR/walls/black-nord.png|" \
    "$OXWM_START_SRC" > "$OXWM_START_DST"
chmod +x "$OXWM_START_DST"

# --- 其他 dotfiles ---
log_info "复制 dunstrc..."
mkdir -p "$USER_HOME/.config/dunst"
cp -f "$PROJECT_DIR"/dotfiles/dunstrc "$USER_HOME/.config/dunst/dunstrc"

log_info "复制 picom.conf..."
mkdir -p "$USER_HOME/.config/picom"
cp -f "$PROJECT_DIR"/dotfiles/picom.conf "$USER_HOME/.config/picom/picom.conf"

log_info "复制 rofi 主题..."
mkdir -p "$USER_HOME/.config/rofi"
cp -f "$PROJECT_DIR"/dotfiles/rofi-theme.rasi "$USER_HOME/.config/rofi/theme.rasi"

log_info "配置文件部署完成"

# ============================================================
# 6. 创建 LightDM 会话入口
# ============================================================
log_step "6/7 创建 LightDM 会话入口..."

DESKTOP_FILE="/usr/share/xsessions/oxwm.desktop"

sudo tee "$DESKTOP_FILE" > /dev/null <<EOF
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

# ============================================================
# 7. 设置壁纸
# ============================================================
log_step "7/7 设置壁纸..."

WALLPAPER_DIR="$USER_HOME/Pictures/wallpapers"
mkdir -p "$WALLPAPER_DIR"

for wallpaper in "$PROJECT_DIR"/walls/*; do
    if [[ -f "$wallpaper" ]]; then
        cp -f "$wallpaper" "$WALLPAPER_DIR/"
        log_info "复制壁纸: $(basename "$wallpaper")"
    fi
done

log_info "壁纸已复制到: $WALLPAPER_DIR"

# ============================================================
# 完成
# ============================================================
log_step "安装完成！"
echo ""
log_info "请重启系统或重新登录，然后在 LightDM 界面选择 'oxwm' 会话"
echo ""
log_info "配置文件位置:"
log_info "  OXWM 配置:  $OXWM_CONFIG_DIR"
log_info "  Dunst:      $USER_HOME/.config/dunst/dunstrc"
log_info "  Picom:      $USER_HOME/.config/picom/picom.conf"
log_info "  Rofi 主题:  $USER_HOME/.config/rofi/theme.rasi"
log_info "  Nemo 动作:  $NEMO_ACTIONS_DIR"
log_info "  启动脚本:   $OXWM_START_DST"
