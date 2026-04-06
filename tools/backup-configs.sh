#!/bin/bash

# 配置文件备份脚本
# 用于备份常用软件的配置文件，方便重装系统后还原

# 注意：不使用 set -e，因为备份脚本需要优雅处理文件不存在的情况

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 备份目录（默认在项目根目录下的 backups 目录）
BACKUP_BASE_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/backup_${TIMESTAMP}"

# 创建临时备份目录（备份完成后会打包并删除）
mkdir -p "$BACKUP_DIR"

# 备份计数器
BACKUP_COUNT=0
SKIP_COUNT=0

# 备份函数
backup_file() {
    local src="$1"
    local dest="$2"
    local desc="$3"
    local link_target
    
    # 检查是否是软链接
    if [ -L "$src" ]; then
        link_target=$(readlink -f "$src")
        # 检查是否指向项目目录
        if [[ "$link_target" == "$PROJECT_ROOT"* ]]; then
            echo -e "${BLUE}⊘${NC} $desc (软链接指向项目目录，跳过)"
            ((SKIP_COUNT++))
            return 1
        else
            # 是软链接但指向其他位置，正常备份
            mkdir -p "$(dirname "$dest")"
            cp -r "$src" "$dest"
            echo -e "${GREEN}✓${NC} $desc (软链接)"
            ((BACKUP_COUNT++))
            return 0
        fi
    elif [ -e "$src" ]; then
        # 创建目标目录
        mkdir -p "$(dirname "$dest")"
        # 复制文件或目录
        cp -r "$src" "$dest"
        echo -e "${GREEN}✓${NC} $desc"
        ((BACKUP_COUNT++))
        return 0
    else
        echo -e "${YELLOW}⊘${NC} $desc (文件不存在，跳过)"
        ((SKIP_COUNT++))
        return 1
    fi
}

# 备份目录函数
backup_dir() {
    local src="$1"
    local dest="$2"
    local desc="$3"
    local link_target
    
    # 检查是否是软链接
    if [ -L "$src" ]; then
        link_target=$(readlink -f "$src")
        # 检查是否指向项目目录
        if [[ "$link_target" == "$PROJECT_ROOT"* ]]; then
            echo -e "${BLUE}⊘${NC} $desc (软链接指向项目目录，跳过)"
            ((SKIP_COUNT++))
            return 1
        else
            # 是软链接但指向其他位置，正常备份
            mkdir -p "$(dirname "$dest")"
            cp -r "$src" "$dest"
            echo -e "${GREEN}✓${NC} $desc (软链接)"
            ((BACKUP_COUNT++))
            return 0
        fi
    elif [ -d "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -r "$src" "$dest"
        echo -e "${GREEN}✓${NC} $desc"
        ((BACKUP_COUNT++))
        return 0
    else
        echo -e "${YELLOW}⊘${NC} $desc (目录不存在，跳过)"
        ((SKIP_COUNT++))
        return 1
    fi
}

echo "=========================================="
echo "  配置文件备份工具"
echo "=========================================="
echo ""
echo "临时备份目录: $BACKUP_DIR"
echo "开始时间: $(date)"
echo ""

# 注意：mint-dwm 项目目录本身不备份（通过 git 管理，重装后可直接克隆）
# 以下文件通过 install.sh 创建软链接，指向项目 config 目录，也无需备份：
#   - ~/.Xresources -> ~/.config/mint-dwm/config/.Xresources
#   - ~/.local/share/nemo/actions -> ~/.config/mint-dwm/config/nemo/actions
#   - ~/.config/alacritty/alacritty.toml -> ~/.config/mint-dwm/config/alacritty.toml
#   - ~/.config/dunst/dunstrc -> ~/.config/mint-dwm/config/dunstrc
#   - ~/.config/picom/picom.conf -> ~/.config/mint-dwm/config/picom.conf
#   - ~/.config/mpv/mpv.conf -> ~/.config/mint-dwm/config/mpv.conf
#   - ~/.config/rofi/config.rasi -> ~/.config/mint-dwm/config/rofi-theme.rasi (或其他 rofi 配置)

# 1. MPV 脚本目录（如果存在且不是软链接）
echo ""
echo "【媒体播放器配置】"
backup_dir "$HOME/.config/mpv/scripts" "$BACKUP_DIR/mpv/scripts" "MPV 脚本目录"

# 2. Rofi 主题目录（如果存在且不是软链接）
echo ""
echo "【应用启动器配置】"
backup_dir "$HOME/.config/rofi/themes" "$BACKUP_DIR/rofi/themes" "Rofi 主题目录"

# 3. Nemo 文件管理器配置
echo ""
echo "【文件管理器配置】"
backup_dir "$HOME/.config/nemo" "$BACKUP_DIR/nemo/config" "Nemo 配置目录"
backup_dir "$HOME/.local/share/nemo/scripts" "$BACKUP_DIR/nemo/scripts" "Nemo 自定义脚本"
backup_dir "$HOME/.local/share/nemo/search-helpers" "$BACKUP_DIR/nemo/search-helpers" "Nemo 搜索助手"
# 注意：~/.local/share/nemo/actions 通过软链接指向项目目录，无需备份

# 4. Fcitx5 输入法
echo ""
echo "【输入法配置】"
backup_dir "$HOME/.config/fcitx5" "$BACKUP_DIR/fcitx5" "Fcitx5 配置目录"
backup_dir "$HOME/.local/share/fcitx5/pinyin" "$BACKUP_DIR/fcitx5/pinyin" "Fcitx5 自定义词组和词库"
backup_dir "$HOME/.local/share/fcitx5/themes" "$BACKUP_DIR/fcitx5/themes" "Fcitx5 自定义主题"

# 5. Git 配置
echo ""
echo "【Git 配置】"
backup_file "$HOME/.gitconfig" "$BACKUP_DIR/git/.gitconfig" "Git 全局配置"
backup_file "$HOME/.gitignore_global" "$BACKUP_DIR/git/.gitignore_global" "Git 全局忽略文件"

# 6. SSH 配置
echo ""
echo "【SSH 配置】"
backup_dir "$HOME/.ssh" "$BACKUP_DIR/ssh" "SSH 配置目录（包含密钥）"

# 7. GPG 配置
echo ""
echo "【GPG 配置】"
backup_dir "$HOME/.gnupg" "$BACKUP_DIR/gnupg" "GPG 配置目录"

# 8. 系统字体配置
echo ""
echo "【字体配置】"
backup_file "$HOME/.fonts.conf" "$BACKUP_DIR/fonts/.fonts.conf" "字体配置"
backup_dir "$HOME/.local/share/fonts" "$BACKUP_DIR/fonts/local_fonts" "本地字体目录"

# 9. GTK 主题配置
echo ""
echo "【GTK 主题配置】"
backup_file "$HOME/.config/gtk-3.0/settings.ini" "$BACKUP_DIR/gtk/gtk-3.0/settings.ini" "GTK3 设置"
backup_file "$HOME/.config/gtk-4.0/settings.ini" "$BACKUP_DIR/gtk/gtk-4.0/settings.ini" "GTK4 设置"

# 10. 其他常用配置
echo ""
echo "【其他配置】"
backup_file "$HOME/.bashrc" "$BACKUP_DIR/shell/.bashrc" "Bash 配置"
backup_file "$HOME/.bash_aliases" "$BACKUP_DIR/shell/.bash_aliases" "Bash 别名"
backup_file "$HOME/.profile" "$BACKUP_DIR/shell/.profile" "Profile 配置"
backup_file "$HOME/.zshrc" "$BACKUP_DIR/shell/.zshrc" "Zsh 配置（如果使用）"
backup_file "$HOME/.vimrc" "$BACKUP_DIR/vim/.vimrc" "Vim 配置"
backup_dir "$HOME/.vim" "$BACKUP_DIR/vim/.vim" "Vim 插件目录"

# 11. 系统服务配置（systemd user units）
echo ""
echo "【系统服务配置】"
if [ -d "$HOME/.config/systemd/user" ]; then
    backup_dir "$HOME/.config/systemd/user" "$BACKUP_DIR/systemd/user" "Systemd 用户服务"
fi

# 12. 环境变量配置
echo ""
echo "【环境变量配置】"
backup_file "$HOME/.pam_environment" "$BACKUP_DIR/env/.pam_environment" "PAM 环境变量"
backup_file "$HOME/.xsessionrc" "$BACKUP_DIR/env/.xsessionrc" "X Session 配置"

# 创建备份信息文件
cat > "$BACKUP_DIR/backup_info.txt" << EOF
配置文件备份信息
==================

备份时间: $(date)
备份目录: $BACKUP_DIR
系统信息: $(uname -a)
用户: $USER
主目录: $HOME

备份统计:
- 成功备份: $BACKUP_COUNT 项
- 跳过项目: $SKIP_COUNT 项

备份内容:
- MPV 脚本目录（如果存在）
- Rofi 主题目录（如果存在）
- Nemo 文件管理器配置（配置、自定义脚本、搜索助手）
- 输入法配置 (Fcitx5: 配置、自定义词组、词库、主题)
- Git 配置
- SSH 配置
- GPG 配置
- 字体配置
- GTK 主题配置
- Shell 配置
- Vim 配置
- 系统服务配置
- 环境变量配置

还原方法:
使用 restore-configs.sh 脚本还原配置，或手动复制文件到对应位置。
EOF

echo ""
echo "=========================================="
echo "备份完成，正在打包..."
echo "=========================================="
echo ""

# 自动创建压缩包
ARCHIVE_NAME="${BACKUP_BASE_DIR}/backup_${TIMESTAMP}.tar.gz"
echo "正在创建压缩包..."
cd "$BACKUP_BASE_DIR" || exit
if tar -czf "$ARCHIVE_NAME" "backup_${TIMESTAMP}" 2>/dev/null; then
    ARCHIVE_SIZE=$(du -h "$ARCHIVE_NAME" | cut -f1)
    echo -e "${GREEN}✓${NC} 压缩包已创建: $ARCHIVE_NAME (${ARCHIVE_SIZE})"
    
    # 删除临时备份目录
    rm -rf "$BACKUP_DIR"
    echo -e "${GREEN}✓${NC} 已删除临时备份目录"
    
    echo ""
    echo "=========================================="
    echo "备份完成！"
    echo "=========================================="
    echo ""
    echo "备份文件: ${GREEN}$ARCHIVE_NAME${NC}"
    echo "文件大小: ${GREEN}$ARCHIVE_SIZE${NC}"
    echo "成功备份: ${GREEN}$BACKUP_COUNT${NC} 项"
    echo "跳过项目: ${YELLOW}$SKIP_COUNT${NC} 项"
    echo ""
    echo "还原方法:"
    echo "  使用 restore-configs.sh 脚本还原配置"
    echo ""
else
    echo -e "${RED}✗${NC} 创建压缩包失败"
    echo "备份目录保留在: $BACKUP_DIR"
    exit 1
fi
