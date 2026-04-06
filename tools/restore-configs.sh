#!/bin/bash

# 配置文件还原脚本
# 从备份中还原配置文件

# 注意：不使用 set -e，因为还原脚本需要优雅处理文件不存在或用户选择跳过的情况

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_BASE_DIR="${PROJECT_ROOT}/backups"

# 还原计数器
RESTORE_COUNT=0
SKIP_COUNT=0

# 定义可还原的配置项目（使用索引数组确保顺序）
CONFIG_ITEMS=(
    "mpv|媒体播放器配置"
    "rofi|应用启动器配置"
    "nemo|文件管理器配置"
    "fcitx5|输入法配置"
    "git|Git 配置"
    "ssh|SSH 配置"
    "gnupg|GPG 配置"
    "fonts|字体配置"
    "gtk|GTK 主题配置"
    "shell|Shell 配置"
    "vim|Vim 配置"
    "systemd|Systemd 服务配置"
    "env|环境变量配置"
)

# 还原函数
restore_file() {
    local src="$1"
    local dest="$2"
    local desc="$3"
    
    if [ -e "$src" ]; then
        # 如果目标文件已存在，询问是否覆盖
        if [ -e "$dest" ]; then
            echo -e "${YELLOW}⚠${NC} $desc 已存在"
            read -p "  是否覆盖？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "  ${YELLOW}⊘${NC} 跳过"
                ((SKIP_COUNT++))
                return 1
            fi
        fi
        
        # 创建目标目录
        mkdir -p "$(dirname "$dest")" || {
            echo -e "${RED}✗${NC} 无法创建目标目录: $(dirname "$dest")"
            ((SKIP_COUNT++))
            return 1
        }
        # 复制文件或目录
        if ! cp -r "$src" "$dest" 2>/dev/null; then
            echo -e "${RED}✗${NC} 还原失败: $desc"
            ((SKIP_COUNT++))
            return 1
        fi
        echo -e "${GREEN}✓${NC} $desc"
        ((RESTORE_COUNT++))
        return 0
    else
        echo -e "${YELLOW}⊘${NC} $desc (备份中不存在，跳过)"
        ((SKIP_COUNT++))
        return 1
    fi
}

# 列出可用的备份
list_backups() {
    local backups=()
    local index=1
    
    echo "可用的备份："
    echo ""
    
    # 优先查找压缩包备份（现在默认使用压缩包格式）
    for archive in "$BACKUP_BASE_DIR"/backup_*.tar.gz; do
        if [ -f "$archive" ]; then
            name=$(basename "$archive")
            date=$(stat -c %y "$archive" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
            echo "  [$index] $name ($date)"
            backups+=("$archive")
            ((index++))
        fi
    done
    
    # 查找目录备份（兼容旧格式）
    for dir in "$BACKUP_BASE_DIR"/backup_*; do
        if [ -d "$dir" ] && [[ ! "$dir" == *.tar.gz ]]; then
            name=$(basename "$dir")
            date=$(stat -c %y "$dir" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
            echo "  [$index] $name ($date) [目录]"
            backups+=("$dir")
            ((index++))
        fi
    done
    
    echo ""
    echo "备份总数: $((index - 1))"
    echo ""
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未找到任何备份！${NC}"
        echo "请先运行 backup-configs.sh 创建备份。"
        exit 1
    fi
    
    # 让用户选择备份
    while true; do
        read -r -p "请选择要还原的备份编号 (1-$((index - 1))): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((index - 1)) ]; then
            SELECTED_BACKUP="${backups[$((choice - 1))]}"
            break
        else
            echo -e "${RED}无效的选择，请输入 1-$((index - 1)) 之间的数字${NC}"
        fi
    done
}

# 解压压缩包（如果需要）
extract_archive() {
    local archive="$1"
    if [ -f "$archive" ]; then
        echo "检测到压缩包，正在解压..."
        local extract_dir="${BACKUP_BASE_DIR}/temp_extract_$$"
        if ! mkdir -p "$extract_dir"; then
            echo -e "${RED}错误: 无法创建临时解压目录${NC}"
            exit 1
        fi
        
        if ! tar -xzf "$archive" -C "$extract_dir" 2>/dev/null; then
            echo -e "${RED}错误: 解压压缩包失败${NC}"
            rm -rf "$extract_dir"
            exit 1
        fi
        
        # 查找解压后的备份目录
        extracted_backup=$(find "$extract_dir" -maxdepth 1 -type d -name "backup_*" | head -n 1)
        if [ -n "$extracted_backup" ]; then
            SELECTED_BACKUP="$extracted_backup"
            echo -e "${GREEN}✓${NC} 解压完成"
        else
            echo -e "${RED}错误: 无法找到解压后的备份目录${NC}"
            rm -rf "$extract_dir"
            exit 1
        fi
    fi
}

# 显示配置项目选择菜单
select_config_items() {
    local item_count=${#CONFIG_ITEMS[@]}
    
    echo ""
    echo "请选择要还原的配置项目（可多选）"
    echo "=========================================="
    echo ""
    
    for i in "${!CONFIG_ITEMS[@]}"; do
        IFS='|' read -r id desc <<< "${CONFIG_ITEMS[$i]}"
        num=$((i + 1))
        echo "  [$num] $desc"
    done
    
    echo ""
    echo "  [a] 全选"
    echo "  [n] 全不选"
    echo "  [q] 确认选择"
    echo ""
    
    # 初始化选择数组（使用0-based索引）
    declare -g SELECTED_ITEMS=()
    
    while true; do
        read -r -p "请选择 (如: 1,3,5 或 a/q): " -e choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        
        if [ "$choice" = "q" ]; then
            break
        elif [ "$choice" = "a" ]; then
            SELECTED_ITEMS=()
            for ((i=0; i<item_count; i++)); do
                SELECTED_ITEMS+=("$i")
            done
            echo -e "${GREEN}✓${NC} 已全选"
        elif [ "$choice" = "n" ]; then
            SELECTED_ITEMS=()
            echo -e "${YELLOW}⊘${NC} 已全不选"
        elif [[ "$choice" =~ ^[0-9,]+$ ]]; then
            SELECTED_ITEMS=()
            IFS=',' read -ra choices <<< "$choice"
            valid=true
            for c in "${choices[@]}"; do
                c=$(echo "$c" | xargs)
                idx=$((c - 1))
                if [[ "$c" =~ ^[0-9]+$ ]] && [ "$idx" -ge 0 ] && [ "$idx" -lt "$item_count" ]; then
                    SELECTED_ITEMS+=("$idx")
                else
                    echo -e "${RED}无效选项: $c (范围 1-$item_count)${NC}"
                    valid=false
                fi
            done
            if $valid; then
                # 显示用户选择的数字编号
                local display
                for idx in "${SELECTED_ITEMS[@]}"; do
                    display="$display $(($idx + 1)),"
                done
                display=$(echo "$display" | sed 's/,$//')
                echo -e "${GREEN}✓${NC} 已选择:$display"
            fi
        else
            echo -e "${RED}无效输入，请重试${NC}"
        fi
    done
    
    # 按索引排序
    IFS=$'\n' sorted=($(sort -n <<<"${SELECTED_ITEMS[*]}")); unset IFS
    SELECTED_ITEMS=("${sorted[@]}")
    
    if [ ${#SELECTED_ITEMS[@]} -eq 0 ]; then
        echo -e "${YELLOW}未选择任何项目，退出${NC}"
        exit 0
    fi
    
    echo ""
    echo "已选择的项目："
    for i in "${SELECTED_ITEMS[@]}"; do
        IFS='|' read -r id desc <<< "${CONFIG_ITEMS[$i]}"
        echo "  - $desc"
    done
    echo ""
}

# 检查是否选择了指定项目（传入0-based索引）
is_selected() {
    local item="$1"
    for selected in "${SELECTED_ITEMS[@]}"; do
        if [ "$selected" = "$item" ]; then
            return 0
        fi
    done
    return 1
}

# 主程序
echo "=========================================="
echo "  配置文件还原工具"
echo "=========================================="
echo ""

# 检查备份目录是否存在
if [ ! -d "$BACKUP_BASE_DIR" ]; then
    echo -e "${RED}错误: 备份目录不存在！${NC}"
    echo "备份目录路径: $BACKUP_BASE_DIR"
    echo "请先运行 backup-configs.sh 创建备份。"
    exit 1
fi

# 列出并选择备份
list_backups

# 如果是压缩包，先解压
if [[ "$SELECTED_BACKUP" == *.tar.gz ]]; then
    extract_archive "$SELECTED_BACKUP"
fi

# 检查备份目录是否存在
if [ ! -d "$SELECTED_BACKUP" ]; then
    echo -e "${RED}错误: 备份目录不存在！${NC}"
    exit 1
fi

# 显示备份信息
if [ -f "$SELECTED_BACKUP/backup_info.txt" ]; then
    echo ""
    echo "备份信息："
    echo "----------------------------------------"
    cat "$SELECTED_BACKUP/backup_info.txt"
    echo "----------------------------------------"
    echo ""
fi

# 选择要还原的项目
select_config_items

# 确认还原
echo -e "${YELLOW}警告: 还原操作将覆盖现有的配置文件！${NC}"
read -p "确认要继续还原吗？(y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消还原操作。"
    exit 0
fi

echo ""
echo "开始还原配置..."
echo ""

# 注意：mint-dwm 项目目录不备份（通过 git 管理，重装后可直接克隆）
# 以下文件通过 install.sh 创建软链接，指向项目 config 目录，也无需还原：
#   - ~/.Xresources -> ~/.config/mint-dwm/config/.Xresources
#   - ~/.local/share/nemo/actions -> ~/.config/mint-dwm/config/nemo/actions
#   - ~/.config/alacritty/alacritty.toml -> ~/.config/mint-dwm/config/alacritty.toml
#   - ~/.config/dunst/dunstrc -> ~/.config/mint-dwm/config/dunstrc
#   - ~/.config/picom/picom.conf -> ~/.config/mint-dwm/config/picom.conf
#   - ~/.config/mpv/mpv.conf -> ~/.config/mint-dwm/config/mpv.conf
#   - ~/.config/rofi/config.rasi -> ~/.config/mint-dwm/config/rofi-theme.rasi (或其他 rofi 配置)

# 根据选择的项目进行还原（使用0-based索引）
is_selected 0 && {
    echo ""
    echo "【媒体播放器配置】"
    restore_file "$SELECTED_BACKUP/mpv/scripts" "$HOME/.config/mpv/scripts" "MPV 脚本目录"
}

is_selected 1 && {
    echo ""
    echo "【应用启动器配置】"
    restore_file "$SELECTED_BACKUP/rofi/themes" "$HOME/.config/rofi/themes" "Rofi 主题目录"
}

is_selected 2 && {
    echo ""
    echo "【文件管理器配置】"
    restore_file "$SELECTED_BACKUP/nemo/config" "$HOME/.config/nemo" "Nemo 配置目录"
    restore_file "$SELECTED_BACKUP/nemo/scripts" "$HOME/.local/share/nemo/scripts" "Nemo 自定义脚本"
    restore_file "$SELECTED_BACKUP/nemo/search-helpers" "$HOME/.local/share/nemo/search-helpers" "Nemo 搜索助手"
}

is_selected 3 && {
    echo ""
    echo "【输入法配置】"
    restore_file "$SELECTED_BACKUP/fcitx5" "$HOME/.config/fcitx5" "Fcitx5 配置目录"
    restore_file "$SELECTED_BACKUP/fcitx5/pinyin" "$HOME/.local/share/fcitx5/pinyin" "Fcitx5 自定义词组和词库"
    restore_file "$SELECTED_BACKUP/fcitx5/themes" "$HOME/.local/share/fcitx5/themes" "Fcitx5 自定义主题"
}

is_selected 4 && {
    echo ""
    echo "【Git 配置】"
    restore_file "$SELECTED_BACKUP/git/.gitconfig" "$HOME/.gitconfig" "Git 全局配置"
    restore_file "$SELECTED_BACKUP/git/.gitignore_global" "$HOME/.gitignore_global" "Git 全局忽略文件"
}

is_selected 5 && {
    echo ""
    echo "【SSH 配置】"
    echo -e "${YELLOW}⚠${NC} SSH 配置包含敏感信息（密钥）"
    read -p "  是否还原 SSH 配置？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restore_file "$SELECTED_BACKUP/ssh" "$HOME/.ssh" "SSH 配置目录"
        # 设置正确的权限
        if [ -d "$HOME/.ssh" ]; then
            chmod 700 "$HOME/.ssh"
            chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
            chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null || true
            echo -e "${GREEN}✓${NC} 已设置 SSH 目录权限"
        fi
    else
        echo -e "${YELLOW}⊘${NC} 跳过 SSH 配置"
        ((SKIP_COUNT++))
    fi
}

is_selected 6 && {
    echo ""
    echo "【GPG 配置】"
    echo -e "${YELLOW}⚠${NC} GPG 配置包含敏感信息（密钥）"
    read -p "  是否还原 GPG 配置？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restore_file "$SELECTED_BACKUP/gnupg" "$HOME/.gnupg" "GPG 配置目录"
        # 设置正确的权限
        if [ -d "$HOME/.gnupg" ]; then
            chmod 700 "$HOME/.gnupg"
            echo -e "${GREEN}✓${NC} 已设置 GPG 目录权限"
        fi
    else
        echo -e "${YELLOW}⊘${NC} 跳过 GPG 配置"
        ((SKIP_COUNT++))
    fi
}

is_selected 7 && {
    echo ""
    echo "【字体配置】"
    restore_file "$SELECTED_BACKUP/fonts/.fonts.conf" "$HOME/.fonts.conf" "字体配置"
    restore_file "$SELECTED_BACKUP/fonts/local_fonts" "$HOME/.local/share/fonts" "本地字体目录"
}

is_selected 8 && {
    echo ""
    echo "【GTK 主题配置】"
    restore_file "$SELECTED_BACKUP/gtk/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini" "GTK3 设置"
    restore_file "$SELECTED_BACKUP/gtk/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" "GTK4 设置"
}

is_selected 9 && {
    echo ""
    echo "【Shell 配置】"
    restore_file "$SELECTED_BACKUP/shell/.bashrc" "$HOME/.bashrc" "Bash 配置"
    restore_file "$SELECTED_BACKUP/shell/.bash_aliases" "$HOME/.bash_aliases" "Bash 别名"
    restore_file "$SELECTED_BACKUP/shell/.profile" "$HOME/.profile" "Profile 配置"
    restore_file "$SELECTED_BACKUP/shell/.zshrc" "$HOME/.zshrc" "Zsh 配置"
}

is_selected 10 && {
    echo ""
    echo "【Vim 配置】"
    restore_file "$SELECTED_BACKUP/vim/.vimrc" "$HOME/.vimrc" "Vim 配置"
    restore_file "$SELECTED_BACKUP/vim/.vim" "$HOME/.vim" "Vim 插件目录"
}

is_selected 11 && {
    echo ""
    echo "【系统服务配置】"
    restore_file "$SELECTED_BACKUP/systemd/user" "$HOME/.config/systemd/user" "Systemd 用户服务"
}

is_selected 12 && {
    echo ""
    echo "【环境变量配置】"
    restore_file "$SELECTED_BACKUP/env/.pam_environment" "$HOME/.pam_environment" "PAM 环境变量"
    restore_file "$SELECTED_BACKUP/env/.xsessionrc" "$HOME/.xsessionrc" "X Session 配置"
}

# 清理临时解压目录
if [ -d "${BACKUP_BASE_DIR}/temp_extract_$$" ]; then
    echo ""
    read -p "是否删除临时解压目录？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        rm -rf "${BACKUP_BASE_DIR}/temp_extract_$$"
        echo -e "${GREEN}✓${NC} 已清理临时文件"
    fi
fi

echo ""
echo "=========================================="
echo "还原完成！"
echo "=========================================="
echo ""
echo "成功还原: ${GREEN}$RESTORE_COUNT${NC} 项"
echo "跳过项目: ${YELLOW}$SKIP_COUNT${NC} 项"
echo ""
echo -e "${BLUE}提示:${NC}"
echo "1. 某些配置可能需要重启应用程序或重新登录才能生效"
echo "2. SSH 和 GPG 密钥的权限已自动设置"
echo "3. 如果还原了字体，请运行: fc-cache -f -v"
echo ""
