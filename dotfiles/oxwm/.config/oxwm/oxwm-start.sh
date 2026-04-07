#!/bin/bash
# ============================================================
# OXWM 会话启动脚本
# 由 LightDM 选择 "oxwm" 会话时执行
# 负责设置环境变量、启动桌面组件，最后 exec 进入 OXWM
# ============================================================

# ============================================================
# 1. 输入法与国际化环境变量
# ============================================================
# 必须在所有 GUI 程序启动前设置，否则部分应用无法使用中文输入

# 系统语言设为英文（界面），UTF-8 编码保证中文文件名等正常显示
export LANG=en_US.UTF-8

# Fcitx5 输入法环境变量
# XMODIFIERS: X11 输入法框架标识，@im=fcitx 告诉 XIM 客户端使用 fcitx
export XMODIFIERS=@im=fcitx
# GTK2/GTK3 应用通过此变量使用 fcitx 输入法模块
export GTK_IM_MODULE=fcitx
# Qt5/Qt6 应用通过此变量使用 fcitx 输入法模块
export QT_IM_MODULE=fcitx
# SDL 应用（游戏、多媒体）通过此变量使用 fcitx
export SDL_IM_MODULE=fcitx

# 会话管理器标识，部分应用（如 Chrome）依赖此变量判断桌面会话
export SESSION_MANAGER=${SESSION_MANAGER:-local/$(hostname):$(ps -p $$ -o ppid=):oxwm}

# 将 DISPLAY 和 XAUTHORITY 导入 systemd user session
# 使 systemd --user 管理的服务能访问 X11 显示
systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null || true

# ============================================================
# 2. 日志重定向
# ============================================================
# 将本脚本后续所有 stdout/stderr 重定向到日志文件
# 日志超过 1MB 时自动截断，保留最后 100 行

LOGDIR="$HOME/.local/share/oxwm"
LOGFILE="$LOGDIR/oxwm.log"
mkdir -p "$LOGDIR"

if [ -f "$LOGFILE" ] && [ "$(stat -c %s "$LOGFILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    tail -n 100 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
fi

# exec 重定向后，本脚本后续所有输出（包括子进程）都会写入日志
exec > "$LOGFILE" 2>&1
echo "--- oxwm startup at $(date) ---"

# ============================================================
# 3. 显示器电源管理
# ============================================================
# 关闭 DPMS（显示器电源管理信号），防止屏幕自动休眠/黑屏
# 关闭屏幕保护器空白（blank），防止 X11 屏幕保护器触发
xset -dpms &
xset s off &
xset s noblank &

# ============================================================
# 4. 自动设置显示器最佳分辨率
# ============================================================
# 检测主显示器并设置其推荐分辨率（带 + 号的模式）

if command -v xrandr &>/dev/null; then
    # 从 xrandr --listmonitors 获取第一个显示器名称（跳过标题行）
    # 输出示例: "0: +*eDP-1 1920/344x1080/193+0+0 eDP-1"
    PRIMARY=$(xrandr --listmonitors 2>/dev/null | awk 'NR==2{print $4}' | cut -d+ -f1)
    if [[ -n "$PRIMARY" ]]; then
        # 从 xrandr --query 中提取该显示器的推荐模式（带 + 标记的第一行）
        PREFERRED=$(xrandr --query | sed -n "/^$PRIMARY connected/,/^[^ ]/p" | grep '+' | head -1 | awk '{print $1}')
        if [[ -n "$PREFERRED" ]]; then
            xrandr --output "$PRIMARY" --mode "$PREFERRED" &
        fi
    fi
fi

# ============================================================
# 5. 桌面组件路径变量
# ============================================================

DUNSTRC_PATH="$HOME/.config/dunst/dunstrc"
PICOM_PATH="$HOME/.config/picom/picom.conf"
WALLPAPER="$HOME/Pictures/wallpapers/black-nord.png"

# ============================================================
# 6. 防重复启动函数
# ============================================================
# 检查命令是否存在且未运行后才启动，避免重复启动同一服务
# 使用 basename 提取进程名，兼容带完整路径的命令

start_once() {
    if command -v "$1" >/dev/null 2>&1; then
        if ! pgrep -x "$(basename "$1")" >/dev/null 2>&1; then
            "$@" &
        fi
    fi
}

# ============================================================
# 7. 密钥环（gnome-keyring）
# ============================================================
# gnome-keyring 提供 SSH agent、Secret Service（密码存储）、PKCS#11 功能
# 注意：gpg 组件已在 GNOME 3.16（2015年）移除，不再导出 GPG_AGENT_INFO
# 如需 GPG 功能，应使用独立的 gpg-agent（通常由 gnupg 包自动管理）

if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    if ! pgrep -x "gnome-keyring-d" >/dev/null 2>&1; then
        eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh)"
        export SSH_AUTH_SOCK
    fi
fi

# ============================================================
# 8. 桌面组件启动
# ============================================================
# 启动顺序说明：
#   1. polkit: 提权认证代理，其他 GUI 工具（如磁盘管理）需要它弹出密码框
#   2. picom: 合成器，提供窗口阴影、透明、vsync 等视觉效果
#   3. fcitx5: 输入法框架，必须在应用启动前就绪
#   4. clipman: 剪贴板管理器，记录剪贴板历史
#   5. pasystray: PulseAudio 系统托盘，提供音量控制图标
#   6. dunst: 通知守护进程，显示系统/应用通知
#   7. xwallpaper: 设置桌面壁纸

# Polkit 认证代理（lxpolkit）
# 用于 GUI 程序提权时弹出密码输入框（如磁盘管理、软件安装等）
start_once /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1

# PipeWire 音频服务 + Wireplumber 会话管理器
# PipeWire 是 PulseAudio 的现代替代品，wireplumber 负责设备管理和策略
start_once pipewire
start_once pipewire-pulse
start_once wireplumber

# 合成器（后台模式，指定配置文件）
start_once picom -b --config "$PICOM_PATH"

# 输入法框架（守护进程模式）
start_once fcitx5 -d

# 剪贴板管理器
start_once xfce4-clipman

# PulseAudio 系统托盘
start_once pasystray

# 通知守护进程（指定配置文件）
start_once dunst -conf "$DUNSTRC_PATH"

# 壁纸（zoom 模式：等比缩放填满屏幕）
start_once xwallpaper --zoom "$WALLPAPER"

# ============================================================
# 9. 启动 OXWM 窗口管理器
# ============================================================
# exec 替换当前 shell 进程为 oxwm
# 这样 OXWM 成为 session leader，退出时整个会话结束，LightDM 返回登录界面

exec oxwm
