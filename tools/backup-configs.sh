#!/bin/bash

# 配置文件备份脚本 - 使用 whiptail 交互式选择
# 用于备份常用软件的配置文件，方便重装系统后还原

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 检查 whiptail
command -v whiptail &>/dev/null || { echo "错误: 未安装 whiptail，请运行: sudo apt install whiptail"; exit 1; }

# 备份目录
BACKUP_BASE_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_BASE_DIR}/backup_${TIMESTAMP}"

mkdir -p "$BACKUP_DIR"

BACKUP_COUNT=0
SKIP_COUNT=0

backup_item() {
    local src="$1"
    local dest="$2"
    local desc="$3"

    if [ -L "$src" ]; then
        local link_target
        link_target=$(readlink -f "$src")
        if [[ "$link_target" == "$PROJECT_ROOT"* ]]; then
            echo -e "${BLUE}⊘${NC} $desc (软链接指向项目目录，跳过)"
            ((SKIP_COUNT++))
            return 1
        else
            mkdir -p "$(dirname "$dest")"
            cp -r "$src" "$dest"
            echo -e "${GREEN}✓${NC} $desc (软链接)"
            ((BACKUP_COUNT++))
            return 0
        fi
    elif [ -e "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -r "$src" "$dest"
        echo -e "${GREEN}✓${NC} $desc"
        ((BACKUP_COUNT++))
        return 0
    else
        echo -e "${YELLOW}⊘${NC} $desc (不存在，跳过)"
        ((SKIP_COUNT++))
        return 1
    fi
}

# ============================================================
# whiptail 多选菜单
# ============================================================
BACKUP_ITEMS=(
    "mpv"      "MPV 脚本目录"
    "rofi"     "Rofi 主题目录"
    "nemo"     "Nemo 文件管理器配置"
    "fcitx5"   "Fcitx5 输入法配置"
    "git"      "Git 全局配置"
    "ssh"      "SSH 配置 (含密钥)"
    "gnupg"    "GPG 配置 (含密钥)"
    "fonts"    "字体配置"
    "gtk"      "GTK 主题配置"
    "shell"    "Shell 配置 (bash/zsh)"
    "vim"      "Vim 配置"
    "systemd"  "Systemd 用户服务"
    "env"      "环境变量配置"
)

MENU_ARGS=()
for i in "${!BACKUP_ITEMS[@]}"; do
    if (( i % 2 == 0 )); then
        MENU_ARGS+=("${BACKUP_ITEMS[$i]}" "${BACKUP_ITEMS[$i+1]}" "on")
    fi
done

CHOICES=$(whiptail --title "选择要备份的配置" --checklist \
    "空格选择/取消, Tab 切换按钮, 回车确认 (默认全选)" \
    20 60 13 \
    "${MENU_ARGS[@]}" \
    3>&1 1>&2 2>&3) || exit 1

SELECTED=()
for choice in $CHOICES; do
    SELECTED+=("$(echo "$choice" | tr -d '"')")
done

if [[ ${#SELECTED[@]} -eq 0 ]]; then
    whiptail --msgbox "未选择任何项目，退出" 8 40
    exit 0
fi

# ============================================================
# 执行备份
# ============================================================
mkdir -p "$BACKUP_DIR"

for item in "${SELECTED[@]}"; do
    case "$item" in
        mpv)
            backup_item "$HOME/.config/mpv/scripts" "$BACKUP_DIR/mpv/scripts" "MPV 脚本目录"
            ;;
        rofi)
            backup_item "$HOME/.config/rofi/themes" "$BACKUP_DIR/rofi/themes" "Rofi 主题目录"
            ;;
        nemo)
            backup_item "$HOME/.config/nemo" "$BACKUP_DIR/nemo/config" "Nemo 配置目录"
            backup_item "$HOME/.local/share/nemo/scripts" "$BACKUP_DIR/nemo/scripts" "Nemo 自定义脚本"
            backup_item "$HOME/.local/share/nemo/search-helpers" "$BACKUP_DIR/nemo/search-helpers" "Nemo 搜索助手"
            ;;
        fcitx5)
            backup_item "$HOME/.config/fcitx5" "$BACKUP_DIR/fcitx5" "Fcitx5 配置目录"
            backup_item "$HOME/.local/share/fcitx5/pinyin" "$BACKUP_DIR/fcitx5/pinyin" "Fcitx5 自定义词库"
            backup_item "$HOME/.local/share/fcitx5/themes" "$BACKUP_DIR/fcitx5/themes" "Fcitx5 自定义主题"
            ;;
        git)
            backup_item "$HOME/.gitconfig" "$BACKUP_DIR/git/.gitconfig" "Git 全局配置"
            backup_item "$HOME/.gitignore_global" "$BACKUP_DIR/git/.gitignore_global" "Git 全局忽略文件"
            ;;
        ssh)
            backup_item "$HOME/.ssh" "$BACKUP_DIR/ssh" "SSH 配置目录"
            ;;
        gnupg)
            backup_item "$HOME/.gnupg" "$BACKUP_DIR/gnupg" "GPG 配置目录"
            ;;
        fonts)
            backup_item "$HOME/.fonts.conf" "$BACKUP_DIR/fonts/.fonts.conf" "字体配置"
            backup_item "$HOME/.local/share/fonts" "$BACKUP_DIR/fonts/local_fonts" "本地字体目录"
            ;;
        gtk)
            backup_item "$HOME/.config/gtk-3.0/settings.ini" "$BACKUP_DIR/gtk/gtk-3.0/settings.ini" "GTK3 设置"
            backup_item "$HOME/.config/gtk-4.0/settings.ini" "$BACKUP_DIR/gtk/gtk-4.0/settings.ini" "GTK4 设置"
            ;;
        shell)
            backup_item "$HOME/.bashrc" "$BACKUP_DIR/shell/.bashrc" "Bash 配置"
            backup_item "$HOME/.bash_aliases" "$BACKUP_DIR/shell/.bash_aliases" "Bash 别名"
            backup_item "$HOME/.profile" "$BACKUP_DIR/shell/.profile" "Profile 配置"
            backup_item "$HOME/.zshrc" "$BACKUP_DIR/shell/.zshrc" "Zsh 配置"
            ;;
        vim)
            backup_item "$HOME/.vimrc" "$BACKUP_DIR/vim/.vimrc" "Vim 配置"
            backup_item "$HOME/.vim" "$BACKUP_DIR/vim/.vim" "Vim 插件目录"
            ;;
        systemd)
            backup_item "$HOME/.config/systemd/user" "$BACKUP_DIR/systemd/user" "Systemd 用户服务"
            ;;
        env)
            backup_item "$HOME/.pam_environment" "$BACKUP_DIR/env/.pam_environment" "PAM 环境变量"
            backup_item "$HOME/.xsessionrc" "$BACKUP_DIR/env/.xsessionrc" "X Session 配置"
            ;;
    esac
done

# 创建备份信息
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
$(for item in "${SELECTED[@]}"; do echo "- $item"; done)

还原方法:
使用 restore-configs.sh 脚本还原配置。
EOF

# 打包
ARCHIVE_NAME="${BACKUP_BASE_DIR}/backup_${TIMESTAMP}.tar.gz"
cd "$BACKUP_BASE_DIR" || exit
if tar -czf "$ARCHIVE_NAME" "backup_${TIMESTAMP}" 2>/dev/null; then
    ARCHIVE_SIZE=$(du -h "$ARCHIVE_NAME" | cut -f1)
    rm -rf "$BACKUP_DIR"

    whiptail --msgbox \
        "备份完成！\n\n文件: $ARCHIVE_NAME\n大小: $ARCHIVE_SIZE\n成功: $BACKUP_COUNT 项\n跳过: $SKIP_COUNT 项" \
        12 60
else
    whiptail --msgbox "打包失败，临时目录保留在: $BACKUP_DIR" 8 60
    exit 1
fi
