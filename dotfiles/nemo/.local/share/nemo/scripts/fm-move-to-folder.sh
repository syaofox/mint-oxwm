#!/bin/bash
# 获取第一个参数的目录作为基准目录
if [ -z "$1" ]; then exit 0; fi
BASE_DIR=$(dirname "$1")

# 弹出输入框
NEW_NAME=$(zenity --entry --title="新建文件夹" --text="输入新文件夹名称:" --entry-text="New Folder")

# 如果取消或为空则退出
if [ -z "$NEW_NAME" ]; then exit 0; fi

TARGET_DIR="$BASE_DIR/$NEW_NAME"

# 检查重名
if [ -d "$TARGET_DIR" ]; then
    zenity --error --text="文件夹 \"$NEW_NAME\" 已存在！\n操作已取消。"
    exit 1
fi

# 创建目录并移动
mkdir -p "$TARGET_DIR"
for file in "$@"; do
    if [ -e "$file" ] && [ "$file" != "$BASE_DIR" ]; then
        mv "$file" "$TARGET_DIR/"
    fi
done

