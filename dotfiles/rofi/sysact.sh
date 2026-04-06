#!/bin/bash
# 使用 dmenu/rofi 显示系统电源菜单

# 定义选项
shutdown="  Shutdown"
reboot="  Reboot"
logout="  Logout"
lock="  Lock"

# 根据安装情况选择菜单工具 (优先 rofi，其次 dmenu)
if command -v rofi &> /dev/null; then
    menu_cmd="rofi -dmenu -i -p System -theme $HOME/.config/mint-dwm/config/rofi-theme.rasi"
else
    menu_cmd="dmenu -i -p System:"
fi

# 显示菜单
options="$lock\n$logout\n$reboot\n$shutdown"
selected="$(echo -e "$options" | $menu_cmd)"

# 执行操作
case "$selected" in
    "$shutdown")
        systemctl poweroff
        ;;
    "$reboot")
        systemctl reboot
        ;;
    "$logout")
        # 退出 dwm (通过模拟快捷键 Super+Shift+q 触发 dwm 内部的退出流程)
        # 这比 killall 更稳妥，因为它允许 dwm 执行 cleanup() 清理资源
        # 需要安装 xdotool: sudo apt install xdotool
        if command -v xdotool &> /dev/null; then
            xdotool key Super+Shift+q
        else
            # Fallback: 如果没有 xdotool，则使用 kill 发送 SIGTERM
            # -x 确保只杀 dwm 进程
            pkill -u "$USER" -x dwm
        fi
        ;;
    "$lock")
        slock
        ;;
esac

