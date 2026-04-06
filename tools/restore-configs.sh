#!/bin/bash

# 配置文件还原脚本 - 使用 whiptail 交互式选择
# 从备份中还原配置文件

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
BACKUP_BASE_DIR="${PROJECT_ROOT}/backups"

RESTORE_COUNT=0
SKIP_COUNT=0

# ============================================================
# 还原函数
# ============================================================
restore_item() {
    local src="$1"
    local dest="$2"
    local desc="$3"

    if [ ! -e "$src" ]; then
        echo -e "${YELLOW}⊘${NC} $desc (备份中不存在)"
        ((SKIP_COUNT++))
        return 1
    fi

    if [ -e "$dest" ]; then
        if ! whiptail --yesno "$desc 已存在，是否覆盖？" 8 60; then
            echo -e "${YELLOW}⊘${NC} 跳过"
            ((SKIP_COUNT++))
            return 1
        fi
    fi

    mkdir -p "$(dirname "$dest")" || {
        echo -e "${RED}✗${NC} 无法创建目录: $(dirname "$dest")"
        ((SKIP_COUNT++))
        return 1
    }

    if cp -r "$src" "$dest" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $desc"
        ((RESTORE_COUNT++))
        return 0
    else
        echo -e "${RED}✗${NC} 还原失败: $desc"
        ((SKIP_COUNT++))
        return 1
    fi
}

# ============================================================
# 列出可用备份
# ============================================================
list_backups() {
    local backups=()
    local menu_items=()
    local index=1

    for archive in "$BACKUP_BASE_DIR"/backup_*.tar.gz; do
        if [ -f "$archive" ]; then
            local name date_str
            name=$(basename "$archive")
            date_str=$(stat -c %y "$archive" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
            menu_items+=("$index" "$name ($date_str)")
            backups+=("$archive")
            ((index++))
        fi
    done

    for dir in "$BACKUP_BASE_DIR"/backup_*; do
        if [ -d "$dir" ] && [[ ! "$dir" == *.tar.gz ]]; then
            local name date_str
            name=$(basename "$dir")
            date_str=$(stat -c %y "$dir" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
            menu_items+=("$index" "$name ($date_str) [目录]")
            backups+=("$dir")
            ((index++))
        fi
    done

    if [ ${#backups[@]} -eq 0 ]; then
        whiptail --msgbox "未找到任何备份！\n请先运行 backup-configs.sh 创建备份。" 10 50
        exit 1
    fi

    local choice
    choice=$(whiptail --title "选择要还原的备份" --menu \
        "选择一个备份进行还原" \
        20 70 13 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3) || exit 1

    SELECTED_BACKUP="${backups[$((choice - 1))]}"
}

# ============================================================
# 解压压缩包
# ============================================================
extract_archive() {
    local archive="$1"
    if [ -f "$archive" ]; then
        local extract_dir="${BACKUP_BASE_DIR}/temp_extract_$$"
        mkdir -p "$extract_dir" || {
            whiptail --msgbox "无法创建临时解压目录" 8 50
            exit 1
        }

        tar -xzf "$archive" -C "$extract_dir" 2>/dev/null || {
            rm -rf "$extract_dir"
            whiptail --msgbox "解压失败" 8 50
            exit 1
        }

        local extracted_backup
        extracted_backup=$(find "$extract_dir" -maxdepth 1 -type d -name "backup_*" | head -n 1)
        if [ -n "$extracted_backup" ]; then
            SELECTED_BACKUP="$extracted_backup"
        else
            rm -rf "$extract_dir"
            whiptail --msgbox "无法找到解压后的备份目录" 8 50
            exit 1
        fi
    fi
}

# ============================================================
# 主程序
# ============================================================

if [ ! -d "$BACKUP_BASE_DIR" ]; then
    whiptail --msgbox "备份目录不存在！\n路径: $BACKUP_BASE_DIR\n请先运行 backup-configs.sh 创建备份。" 10 60
    exit 1
fi

# 选择备份
list_backups

# 解压
if [[ "$SELECTED_BACKUP" == *.tar.gz ]]; then
    extract_archive "$SELECTED_BACKUP"
fi

if [ ! -d "$SELECTED_BACKUP" ]; then
    whiptail --msgbox "备份目录不存在！" 8 50
    exit 1
fi

# 显示备份信息
if [ -f "$SELECTED_BACKUP/backup_info.txt" ]; then
    whiptail --textbox "$SELECTED_BACKUP/backup_info.txt" 20 70
fi

# ============================================================
# 选择要还原的配置项目
# ============================================================
RESTORE_ITEMS=(
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
for i in "${!RESTORE_ITEMS[@]}"; do
    if (( i % 2 == 0 )); then
        MENU_ARGS+=("${RESTORE_ITEMS[$i]}" "${RESTORE_ITEMS[$i+1]}" "on")
    fi
done

CHOICES=$(whiptail --title "选择要还原的配置" --checklist \
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

# 确认还原
if ! whiptail --yesno "警告: 还原操作将覆盖现有的配置文件！\n\n确认要继续还原吗？" 10 60; then
    echo "已取消还原操作。"
    exit 0
fi

# ============================================================
# 执行还原
# ============================================================
for item in "${SELECTED[@]}"; do
    case "$item" in
        mpv)
            restore_item "$SELECTED_BACKUP/mpv/scripts" "$HOME/.config/mpv/scripts" "MPV 脚本目录"
            ;;
        rofi)
            restore_item "$SELECTED_BACKUP/rofi/themes" "$HOME/.config/rofi/themes" "Rofi 主题目录"
            ;;
        nemo)
            restore_item "$SELECTED_BACKUP/nemo/config" "$HOME/.config/nemo" "Nemo 配置目录"
            restore_item "$SELECTED_BACKUP/nemo/scripts" "$HOME/.local/share/nemo/scripts" "Nemo 自定义脚本"
            restore_item "$SELECTED_BACKUP/nemo/search-helpers" "$HOME/.local/share/nemo/search-helpers" "Nemo 搜索助手"
            ;;
        fcitx5)
            restore_item "$SELECTED_BACKUP/fcitx5" "$HOME/.config/fcitx5" "Fcitx5 配置目录"
            restore_item "$SELECTED_BACKUP/fcitx5/pinyin" "$HOME/.local/share/fcitx5/pinyin" "Fcitx5 自定义词库"
            restore_item "$SELECTED_BACKUP/fcitx5/themes" "$HOME/.local/share/fcitx5/themes" "Fcitx5 自定义主题"
            ;;
        git)
            restore_item "$SELECTED_BACKUP/git/.gitconfig" "$HOME/.gitconfig" "Git 全局配置"
            restore_item "$SELECTED_BACKUP/git/.gitignore_global" "$HOME/.gitignore_global" "Git 全局忽略文件"
            ;;
        ssh)
            if whiptail --yesno "SSH 配置包含敏感信息（密钥），是否还原？" 8 60; then
                restore_item "$SELECTED_BACKUP/ssh" "$HOME/.ssh" "SSH 配置目录"
                if [ -d "$HOME/.ssh" ]; then
                    chmod 700 "$HOME/.ssh"
                    chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
                    chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null || true
                fi
            else
                echo -e "${YELLOW}⊘${NC} 跳过 SSH 配置"
                ((SKIP_COUNT++))
            fi
            ;;
        gnupg)
            if whiptail --yesno "GPG 配置包含敏感信息（密钥），是否还原？" 8 60; then
                restore_item "$SELECTED_BACKUP/gnupg" "$HOME/.gnupg" "GPG 配置目录"
                if [ -d "$HOME/.gnupg" ]; then
                    chmod 700 "$HOME/.gnupg"
                fi
            else
                echo -e "${YELLOW}⊘${NC} 跳过 GPG 配置"
                ((SKIP_COUNT++))
            fi
            ;;
        fonts)
            restore_item "$SELECTED_BACKUP/fonts/.fonts.conf" "$HOME/.fonts.conf" "字体配置"
            restore_item "$SELECTED_BACKUP/fonts/local_fonts" "$HOME/.local/share/fonts" "本地字体目录"
            ;;
        gtk)
            restore_item "$SELECTED_BACKUP/gtk/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini" "GTK3 设置"
            restore_item "$SELECTED_BACKUP/gtk/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" "GTK4 设置"
            ;;
        shell)
            restore_item "$SELECTED_BACKUP/shell/.bashrc" "$HOME/.bashrc" "Bash 配置"
            restore_item "$SELECTED_BACKUP/shell/.bash_aliases" "$HOME/.bash_aliases" "Bash 别名"
            restore_item "$SELECTED_BACKUP/shell/.profile" "$HOME/.profile" "Profile 配置"
            restore_item "$SELECTED_BACKUP/shell/.zshrc" "$HOME/.zshrc" "Zsh 配置"
            ;;
        vim)
            restore_item "$SELECTED_BACKUP/vim/.vimrc" "$HOME/.vimrc" "Vim 配置"
            restore_item "$SELECTED_BACKUP/vim/.vim" "$HOME/.vim" "Vim 插件目录"
            ;;
        systemd)
            restore_item "$SELECTED_BACKUP/systemd/user" "$HOME/.config/systemd/user" "Systemd 用户服务"
            ;;
        env)
            restore_item "$SELECTED_BACKUP/env/.pam_environment" "$HOME/.pam_environment" "PAM 环境变量"
            restore_item "$SELECTED_BACKUP/env/.xsessionrc" "$HOME/.xsessionrc" "X Session 配置"
            ;;
    esac
done

# 清理临时目录
if [ -d "${BACKUP_BASE_DIR}/temp_extract_$$" ]; then
    if whiptail --yesno "是否删除临时解压目录？" 8 50; then
        rm -rf "${BACKUP_BASE_DIR}/temp_extract_$$"
    fi
fi

# 完成提示
whiptail --msgbox \
    "还原完成！\n\n成功: $RESTORE_COUNT 项\n跳过: $SKIP_COUNT 项\n\n提示:\n1. 某些配置需重启应用或重新登录\n2. SSH/GPG 权限已自动设置\n3. 如还原字体请运行: fc-cache -f -v" \
    16 60
