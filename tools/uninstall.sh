#!/bin/bash
# 卸载 OXWM 及所有相关配置
# 安全移除符号链接和安装的文件，不触及用户自行修改的内容

set -uo pipefail

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

USER_HOME="$HOME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DOTFILE_PACKAGES=(oxwm dunst picom rofi nemo)

remove_symlinks() {
    local pkg="$1"
    local pkg_dir="$PROJECT_DIR/dotfiles/$pkg"

    [[ ! -d "$pkg_dir" ]] && return 0

    local rel_path
    while IFS= read -r rel_path; do
        rel_path="${rel_path#./}"
        local target="$USER_HOME/$rel_path"
        if [[ -L "$target" ]]; then
            local link_target
            link_target="$(readlink -f "$target" 2>/dev/null || true)"
            if [[ "$link_target" == "$PROJECT_DIR/dotfiles/$pkg/$rel_path" ]]; then
                rm -f "$target"
                log_info "  移除链接: $target"
            fi
        fi
    done < <(cd "$pkg_dir" && find . -type f -o -type l)
}

remove_empty_dirs() {
    for dir in \
        "$USER_HOME/.config/oxwm" \
        "$USER_HOME/.config/dunst" \
        "$USER_HOME/.config/picom" \
        "$USER_HOME/.config/rofi" \
        "$USER_HOME/.local/share/nemo/actions" \
        "$USER_HOME/.local/share/nemo/scripts"; do
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            rmdir "$dir" 2>/dev/null
        fi
    done
}

log_step "卸载 OXWM 配置..."

for pkg in "${DOTFILE_PACKAGES[@]}"; do
    remove_symlinks "$pkg"
done

remove_empty_dirs

log_step "移除 LightDM 会话入口..."
if [[ -f "/usr/share/xsessions/oxwm.desktop" ]]; then
    sudo rm -f /usr/share/xsessions/oxwm.desktop
    log_info "会话入口已移除"
fi

log_step "移除 OXWM 二进制..."
if command -v oxwm &>/dev/null; then
    sudo rm -f "$(command -v oxwm)"
    log_info "OXWM 二进制已移除"
fi

log_step "移除 Zig 编译器..."
ZIG_DIR="/opt/zig-*-linux-0.15.2"
if ls -d $ZIG_DIR 1>/dev/null 2>&1; then
    sudo rm -rf $ZIG_DIR
    sudo rm -f /usr/local/bin/zig
    log_info "Zig 编译器已移除"
fi

log_step "移除 Nerd Font..."
if ls "$USER_HOME/.local/share/fonts/JetBrainsMono"*.ttf 1>/dev/null 2>&1; then
    rm -f "$USER_HOME/.local/share/fonts/JetBrainsMono"*.ttf
    fc-cache -f "$USER_HOME/.local/share/fonts"
    log_info "Nerd Font 已移除"
fi

echo ""
log_info "卸载完成"
log_warn "以下内容未自动删除，请手动处理:"
log_warn "  - 壁纸: $USER_HOME/Pictures/wallpapers/"
log_warn "  - 备份: $PROJECT_DIR/backups/"
log_warn "  - 系统依赖包 (apt remove ...)"
