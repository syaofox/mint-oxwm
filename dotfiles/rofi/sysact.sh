#!/bin/bash
# 使用 rofi 显示系统电源菜单

# 定义选项
shutdown="  Shutdown"
reboot="  Reboot"
logout="  Logout"
lock="  Lock"

menu_cmd="rofi -dmenu -i -p System -theme theme"

options="$lock\n$logout\n$reboot\n$shutdown"
selected="$(echo -e "$options" | $menu_cmd)"

case "$selected" in
    "$shutdown") systemctl poweroff ;;
    "$reboot")    systemctl reboot ;;
    "$logout")    pkill -x oxwm ;;
    "$lock")      loginctl lock-session 2>/dev/null || slock ;;
esac
