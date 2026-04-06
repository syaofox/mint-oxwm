#!/bin/bash
# ============================================================
# ZRAM 一键配置脚本（平衡版：75% 物理内存 + swappiness=150）
# 适用场景：ComfyUI + Wan2.2 视频模型，CPU 负载不高
# 要求：sudo 权限，Linux Mint / Ubuntu / Debian 等
# ============================================================

set -euo pipefail

# 检查 root 权限
if [[ "$EUID" -ne 0 ]]; then
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

log_info() { echo "[INFO] $1"; }

# ------------------------------------------------------------
# 1. 创建 ZRAM 配置脚本（大小 = 物理内存的 75%）
# ------------------------------------------------------------
log_info "创建 ZRAM 配置脚本 /usr/local/sbin/zram-setup ..."

cat > /usr/local/sbin/zram-setup <<'EOF'
#!/bin/bash
# ZRAM 设备初始化脚本（由 systemd 服务调用）

set -e

# 获取物理内存大小（单位：KiB）
mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
# 大小 = 物理内存 * 75% = mem_total KiB * 1024 * 75 / 100 = 字节
zram_size=$((mem_total * 1024 * 75 / 100))

# 1. 安全重置现有 zram0 设备（避免 rmmod 失败）
swapoff /dev/zram0 2>/dev/null || true
echo 1 > /sys/block/zram0/reset 2>/dev/null || true

# 2. 加载 zram 模块（如果已加载则仅确保 num_devices）
modprobe zram num_devices=1

# 3. 设置压缩算法（优先 zstd，其次 lz4，否则内核默认）
if [ -f /sys/block/zram0/comp_algorithm ]; then
    if grep -q zstd /sys/block/zram0/comp_algorithm; then
        echo zstd > /sys/block/zram0/comp_algorithm
        echo "[INFO] 压缩算法: zstd"
    elif grep -q lz4 /sys/block/zram0/comp_algorithm; then
        echo lz4 > /sys/block/zram0/comp_algorithm
        echo "[INFO] 压缩算法: lz4"
    else
        echo "[WARN] 无法设置 zstd/lz4，使用内核默认算法"
    fi
fi

# 4. 设置 ZRAM 大小
echo $zram_size > /sys/block/zram0/disksize

# 5. 格式化为 swap 并启用
mkswap /dev/zram0
# 临时设置 swappiness 为 150（永久生效由 sysctl 配置负责）
sysctl vm.swappiness=150 >/dev/null
swapon -p 100 /dev/zram0

echo "[INFO] ZRAM 已启用，大小 = $((zram_size / 1024 / 1024)) MiB (物理内存的 75%)"
EOF

chmod +x /usr/local/sbin/zram-setup
log_info "配置脚本创建完成"

# ------------------------------------------------------------
# 2. 创建 systemd 服务（开机自启）
# ------------------------------------------------------------
log_info "创建 systemd 服务 /etc/systemd/system/zram-setup.service ..."

cat > /etc/systemd/system/zram-setup.service <<'EOF'
[Unit]
Description=ZRAM Setup Service for ComfyUI
After=local-fs.target
Before=swap.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/zram-setup
RemainAfterExit=yes

[Install]
WantedBy=swap.target
EOF

systemctl daemon-reload
systemctl enable zram-setup.service
log_info "systemd 服务已启用"

# ------------------------------------------------------------
# 3. 永久设置 vm.swappiness = 150
# ------------------------------------------------------------
log_info "设置 vm.swappiness = 150（永久生效）..."

SYSCTL_CONF="/etc/sysctl.d/99-zram-swappiness.conf"
if grep -q "^vm.swappiness" "$SYSCTL_CONF" 2>/dev/null; then
    sed -i 's/^vm.swappiness.*/vm.swappiness=150/' "$SYSCTL_CONF"
else
    echo "vm.swappiness=150" > "$SYSCTL_CONF"
fi
sysctl -p "$SYSCTL_CONF" >/dev/null
log_info "swappiness 已永久设置为 150"

# ------------------------------------------------------------
# 4. 立即启动 ZRAM（无需重启）
# ------------------------------------------------------------
log_info "立即启动 ZRAM 服务..."
systemctl start zram-setup.service

# ------------------------------------------------------------
# 5. 验证配置
# ------------------------------------------------------------
echo ""
echo "==================== ZRAM 状态 ===================="
swapon --show
echo ""
zramctl
echo ""
echo "==================== swappiness 当前值 ===================="
sysctl vm.swappiness
echo "========================================================"
echo ""
echo "✅ ZRAM 配置完成！"
echo "   - ZRAM 大小 = 物理内存的 75%"
echo "   - 压缩算法 = zstd（优先）"
echo "   - swappiness = 150（已永久生效）"
echo "   - 开机自动启动"
echo ""
echo "💡 提示：如需调整 ZRAM 大小，请编辑 /usr/local/sbin/zram-setup 中的百分比（75）"