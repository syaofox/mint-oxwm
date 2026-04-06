#!/bin/bash

# 环境变量
export LANG=en_US.UTF-8
export XMODIFIERS=@im=fcitx
export QT_IM_MODULE=fcitx
export GTK_IM_MODULE=fcitx
export SDL_IM_MODULE=fcitx
export SESSION_MANAGER=${SESSION_MANAGER:-local/$(hostname):$(ps -p $$ -o ppid=):oxwm}
systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null || true

# 日志记录
# 将标准输出和标准错误重定向到日志文件，限制日志大小
LOGDIR="$HOME/.local/share/oxwm"
LOGFILE="$LOGDIR/oxwm.log"
mkdir -p "$LOGDIR"
if [ -f "$LOGFILE" ] && [ $(stat -c %s "$LOGFILE" 2>/dev/null || echo 0) -gt 1048576 ]; then
    tail -n 100 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
fi
exec > "$LOGFILE" 2>&1
echo "--- oxwm startup at $(date) ---"

xset -dpms &
xset s off &
xset s noblank &

# 自动设置最佳分辨率
if command -v xrandr &>/dev/null; then
    PRIMARY=$(xrandr --listmonitors 2>/dev/null | awk 'NR==2{print $4}' | cut -d+ -f1)
    if [[ -n "$PRIMARY" ]]; then
        PREFERRED=$(xrandr --query | sed -n "/^$PRIMARY connected/,/^[^ ]/p" | grep '+' | head -1 | awk '{print $1}')
        if [[ -n "$PREFERRED" ]]; then
            xrandr --output "$PRIMARY" --mode "$PREFERRED" &
        fi
    fi
fi

# 定义变量
DUNSTRC_PATH="$HOME/.config/dunst/dunstrc"
PICOM_PATH="$HOME/.config/picom/picom.conf"
WALLPAPER="$HOME/Pictures/wallpapers/black-nord.png"

# 安全启动函数
start_once() {
    if command -v "$1" >/dev/null 2>&1; then
        # 使用 basename 提取命令名，确保能正确检测带路径的程序
        if ! pgrep -x "$(basename "$1")" >/dev/null 2>&1; then
            "$@" &
        fi
    fi
}


# gnome-keyring
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    # 只有当 keyring 守护进程未运行时才启动
    if ! pgrep -x "gnome-keyring-d" >/dev/null 2>&1; then
        eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh,gpg)"
        export SSH_AUTH_SOCK
        export GPG_AGENT_INFO
    fi
fi


# 提权代理
start_once /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
start_once picom -b --config "$PICOM_PATH"
start_once fcitx5 -d
start_once xfce4-clipman
start_once pasystray
start_once dunst -conf "$DUNSTRC_PATH"
start_once xwallpaper --zoom "$WALLPAPER"


# 启动 oxwm
exec oxwm