#!/bin/bash
set -e

# ================================================================
# [17] 打包 Recovery 卡刷包 (flashable zip)
# ----------------------------------------------------------------
# 将构建产物整合进 pack/ 模板，生成可直接在 Recovery 中刷入的卡刷包：
#   pack/boot.img          (u-boot, 静态)  -> boot   分区
#   xiaomi-k20pro-boot.img (内核 boot)     -> cache  分区 (改名 cache.img)
#   rootfs.img             (根文件系统)    -> userdata 分区 (改名 system.img)
#   pack/firmware-update/logo.img (静态)   -> logo   分区
# 分区映射由 pack/META-INF/.../updater-script 定义。
# ================================================================

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PACK_SRC="${PACK_SRC:-$SCRIPT_DIR/pack}"
IMAGE_NAME="${IMAGE_NAME:-rootfs.img}"
BOOT_IMG="${BOOT_IMG:-xiaomi-k20pro-boot.img}"
SYSTEM_TYPE="${SYSTEM_TYPE:-system}"
KERNEL_VERSION="${KERNEL_VERSION:-unknown}"
FLASHABLE_ZIP="${FLASHABLE_ZIP:-flashable-${SYSTEM_TYPE}-${KERNEL_VERSION}.zip}"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17] 📦 打包 Recovery 卡刷包"

# ---------- 依赖检查 ----------
if ! command -v zip >/dev/null 2>&1; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17] ❌ 缺少 zip 命令，请安装 zip"
    exit 1
fi

# ---------- 输入检查 ----------
if [ ! -f "$IMAGE_NAME" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17] ❌ 缺少根文件系统镜像: $IMAGE_NAME"
    exit 1
fi
if [ ! -f "$BOOT_IMG" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17] ❌ 缺少内核 boot 镜像: $BOOT_IMG"
    exit 1
fi
if [ ! -d "$PACK_SRC" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17] ❌ 缺少卡刷包模板目录: $PACK_SRC"
    exit 1
fi
if [ ! -f "$PACK_SRC/boot.img" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17] ❌ 模板缺少 u-boot: $PACK_SRC/boot.img"
    exit 1
fi

# ---------- 准备打包工作目录 (放在当前目录以便对大镜像使用硬链接, 避免额外占用磁盘) ----------
WORK_DIR="$(pwd)/.pack-build"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 复制模板 (META-INF / boot.img / firmware-update 等)
cp -r "$PACK_SRC"/. "$WORK_DIR"/

# boot(内核) -> cache.img, rootfs -> system.img
# 优先使用硬链接(同一文件系统, 零额外占用), 失败则回退到拷贝
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17]   └─ $BOOT_IMG  ->  cache.img"
ln -f "$BOOT_IMG" "$WORK_DIR/cache.img" 2>/dev/null || cp "$BOOT_IMG" "$WORK_DIR/cache.img"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17]   └─ $IMAGE_NAME  ->  system.img"
ln -f "$IMAGE_NAME" "$WORK_DIR/system.img" 2>/dev/null || cp "$IMAGE_NAME" "$WORK_DIR/system.img"

# ---------- 生成卡刷包 ----------
OUT="$(pwd)/$FLASHABLE_ZIP"
rm -f "$OUT"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17]   └─ 生成卡刷包: $FLASHABLE_ZIP"
(
    cd "$WORK_DIR"
    # -r 递归, -X 不存额外属性; 备份/隐藏文件不打包
    zip -r -X "$OUT" \
        META-INF \
        boot.img \
        cache.img \
        system.img \
        firmware-update \
        -x '*~' -x '*/.*'
)

rm -rf "$WORK_DIR"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [17] ✅ 卡刷包完成"
ls -lh "$OUT"
