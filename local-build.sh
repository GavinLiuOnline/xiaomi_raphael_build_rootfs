#!/bin/bash
set -e

# ================================================================
# 本地构建脚本 - 适用于任何架构主机，目标始终为 arm64
# 用法:
#   ./local-build.sh                      # 交互式选择
#   ./local-build.sh [系统类型] [内核版本] [桌面环境]   # 直接参数
#
# 示例:
#   ./local-build.sh ubuntu-phosh 6.18 phosh-full
#   ./local-build.sh debian-server 7.0
# ================================================================

# ---------- 默认参数 ----------
KERNEL_REPO="${KERNEL_REPO:-GengWei1997/linux-xiaomi-raphael-uboot}"
BOOTSTRAP_TOOL="${BOOTSTRAP_TOOL:-mmdebstrap}"
TARGET_ARCH="arm64"

# ---------- 颜色输出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} $1"; }
ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
header(){ echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ================================================================
# 交互式选择菜单
# ================================================================
interactive_select() {
    header "欢迎使用 Xiaomi Raphael 系统镜像构建工具"
    echo "请选择构建配置："

    # ── 1. 选择系统系列 ──
    echo ""
    echo -e "${BOLD}1) 选择系统系列${NC}"
    echo "  1) Debian（稳定、软件包较旧）"
    echo "  2) Ubuntu（较新、软件包更新）"
    read -r -p "  请输入 [1/2] (默认: 2): " os_family_choice
    case "${os_family_choice:-2}" in
        1) OS_FAMILY="debian" ;;
        2) OS_FAMILY="ubuntu" ;;
        *) OS_FAMILY="ubuntu" ;;
    esac

    # ── 2. 选择系统版本 ──
    echo ""
    echo -e "${BOLD}2) 选择系统版本${NC}"
    if [ "$OS_FAMILY" = "debian" ]; then
        echo "  1) trixie    (Debian 13 - 测试版)"
        echo "  2) bookworm  (Debian 12 - 稳定版)"
        read -r -p "  请输入 [1/2] (默认: 1): " deb_ver_choice
        case "${deb_ver_choice:-1}" in
            1) DEBIAN_VERSION="trixie" ;;
            2) DEBIAN_VERSION="bookworm" ;;
            *) DEBIAN_VERSION="trixie" ;;
        esac
        UBUNTU_VERSION=""
        echo "  已选择: ${DEBIAN_VERSION}"
    else
        echo "  1) resolute  (Ubuntu 25.04)"
        echo "  2) noble     (Ubuntu 24.04 LTS)"
        echo "  3) jammy     (Ubuntu 22.04 LTS)"
        read -r -p "  请输入 [1/3] (默认: 3): " ubu_ver_choice
        case "${ubu_ver_choice:-3}" in
            1) UBUNTU_VERSION="resolute" ;;
            2) UBUNTU_VERSION="noble" ;;
            3) UBUNTU_VERSION="jammy" ;;
            *) UBUNTU_VERSION="resolute" ;;
        esac
        DEBIAN_VERSION=""
        echo "  已选择: ${UBUNTU_VERSION}"
    fi

    # ── 3. 选择系统类型 ──
    echo ""
    echo -e "${BOLD}3) 选择系统类型${NC}"
    echo "  1) server     (无桌面环境，最小化系统)"
    echo "  2) gnome      (GNOME 桌面)"
    echo "  3) phosh      (Phosh 手机界面)"
    read -r -p "  请输入 [1/3] (默认: 1): " type_choice
    case "${type_choice:-1}" in
        1) SYSTEM_SUBTYPE="server" ;;
        2) SYSTEM_SUBTYPE="gnome" ;;
        3) SYSTEM_SUBTYPE="phosh" ;;
        *) SYSTEM_SUBTYPE="phosh" ;;
    esac
    SYSTEM_TYPE="${OS_FAMILY}-${SYSTEM_SUBTYPE}"

    # ── 4. 桌面环境细节（仅 phosh） ──
    if [ "$SYSTEM_SUBTYPE" = "phosh" ]; then
        echo ""
        echo -e "${BOLD}4) 选择 Phosh 桌面配置${NC}"
        echo "  1) phosh-full  (完整安装，含设置中心)"
        echo "  2) phosh-core  (最小化 Phosh)"
        echo "  3) phosh-phone (含手机组件 ofono/tweaks)"
        read -r -p "  请输入 [1/3] (默认: 1): " phosh_choice
        case "${phosh_choice:-1}" in
            1) DESKTOP_ENV="phosh-full" ;;
            2) DESKTOP_ENV="phosh-core" ;;
            3) DESKTOP_ENV="phosh-phone" ;;
            *) DESKTOP_ENV="phosh-full" ;;
        esac
    elif [ "$SYSTEM_SUBTYPE" = "gnome" ]; then
        DESKTOP_ENV="gnome"
    else
        DESKTOP_ENV=""
    fi

    # ── 5. 选择内核版本 ──
    echo ""
    echo -e "${BOLD}5) 选择内核版本${NC}"
    echo "  1) 7.0   (主线最新版)"
    echo "  2) 6.18  (稳定版)"
    read -r -p "  请输入 [1/2] (默认: 1): " kern_choice
    case "${kern_choice:-1}" in
        1) KERNEL_VERSION="7.0" ;;
        2) KERNEL_VERSION="6.18" ;;
        *) KERNEL_VERSION="6.18" ;;
    esac

    # ── 确认信息 ──
    echo ""
    header "构建配置确认"
    echo -e "  ${BOLD}系统类型:${NC}     ${OS_FAMILY^} ${SYSTEM_SUBTYPE}"
    echo -e "  ${BOLD}系统版本:${NC}     $( [ -n "$DEBIAN_VERSION" ] && echo "$DEBIAN_VERSION" || echo "$UBUNTU_VERSION" )"
    [ -n "$DESKTOP_ENV" ] && echo -e "  ${BOLD}桌面环境:${NC}     ${DESKTOP_ENV}"
    echo -e "  ${BOLD}内核版本:${NC}     ${KERNEL_VERSION}"
    echo -e "  ${BOLD}目标架构:${NC}     ${TARGET_ARCH}"
    echo ""

    read -r -p "确认以上配置并开始构建？[Y/n] " confirm
    case "${confirm:-Y}" in
        y|Y|yes|Yes|YES|"") ;;
        *) echo "已取消"; exit 0 ;;
    esac
}

# ================================================================
# 检查架构
# ================================================================
check_architecture() {
    local host_arch
    host_arch=$(uname -m)

    echo ""
    info "主机架构: ${host_arch}  →  目标架构: ${TARGET_ARCH} (aarch64)"

    case "$host_arch" in
        aarch64|arm64)
            info "原生 arm64 构建"
            NEED_QEMU=false
            ;;
        x86_64|amd64)
            warn "x86_64 主机，需要 qemu-user-static 跨架构编译"
            NEED_QEMU=true
            ;;
        *)
            warn "未知架构 ${host_arch}，将尝试 qemu-user-static"
            NEED_QEMU=true
            ;;
    esac
}

# ================================================================
# 安装依赖
# ================================================================
install_dependencies() {
    info "检查并安装依赖..."

    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    else
        error "不支持的包管理器，请手动安装依赖"
        exit 1
    fi

    local pkgs=()
    case "$PKG_MANAGER" in
        apt-get)
            pkgs=(curl wget p7zip-full zip sudo)
            [ "$BOOTSTRAP_TOOL" = "mmdebstrap" ] && pkgs+=(mmdebstrap) || pkgs+=(debootstrap)
            [ "$NEED_QEMU" = true ] && pkgs+=(qemu-user-static binfmt-support)
            ;;
        dnf)
            pkgs=(curl wget p7zip zip sudo)
            [ "$BOOTSTRAP_TOOL" = "mmdebstrap" ] && pkgs+=(mmdebstrap) || pkgs+=(debootstrap)
            [ "$NEED_QEMU" = true ] && pkgs+=(qemu-user-static)
            ;;
        pacman)
            pkgs=(curl wget p7zip zip sudo)
            [ "$BOOTSTRAP_TOOL" = "mmdebstrap" ] && pkgs+=(mmdebstrap) || pkgs+=(debootstrap)
            [ "$NEED_QEMU" = true ] && pkgs+=(qemu-user-static binfmt-qemu-static)
            ;;
    esac

    local to_install=()
    for pkg in "${pkgs[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            case "$PKG_MANAGER" in
                apt-get) ! dpkg -s "$pkg" &>/dev/null 2>&1 && to_install+=("$pkg") ;;
                *) to_install+=("$pkg") ;;
            esac
        fi
    done

    # 特殊：检查 mmdebstrap / debootstrap 命令
    for cmd in mmdebstrap debootstrap; do
        if ! command -v "$cmd" &>/dev/null; then
            case "$PKG_MANAGER" in
                apt-get) ! dpkg -s "$cmd" &>/dev/null 2>&1 && to_install+=("$cmd") ;;
            esac
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        info "安装依赖: ${to_install[*]}"
        case "$PKG_MANAGER" in
            apt-get) sudo apt-get update -qq && sudo apt-get install -y "${to_install[@]}" ;;
            dnf)     sudo dnf install -y "${to_install[@]}" ;;
            pacman)  sudo pacman -S --noconfirm "${to_install[@]}" ;;
        esac
        ok "依赖安装完成"
    else
        ok "所有依赖已满足"
    fi

    if [ "$NEED_QEMU" = true ]; then
        if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
            warn "binfmt 未注册，尝试配置..."
            case "$PKG_MANAGER" in
                apt-get)
                    sudo systemctl restart systemd-binfmt 2>/dev/null || true
                    if [ -f /usr/bin/qemu-aarch64-static ]; then
                        echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F' | sudo tee /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
                    fi
                    ;;
            esac
        fi
        ok "qemu-user-static 配置完成"
    fi
}

# ================================================================
# 下载内核包和 boot.img
# ================================================================
check_local_kernel() {
    local kernel_dir="xiaomi-raphael-debs_${KERNEL_VERSION}"

    header "检查本地内核文件..."

    mkdir -p "${kernel_dir}"

    local missing=false
    local files=(
        "linux-image-xiaomi-raphael.deb"
        "linux-headers-xiaomi-raphael.deb"
        "firmware-xiaomi-raphael.deb"
    )
    if [[ "$SYSTEM_TYPE" == *"phosh"* || "$SYSTEM_TYPE" == *"gnome"* ]]; then
        files+=("alsa-xiaomi-raphael.deb")
    fi

    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            cp "$f" "${kernel_dir}/${f}"
            ok "复制到 ${kernel_dir}/${f}"
        elif [ -f "${kernel_dir}/${f}" ]; then
            ok "已存在 ${kernel_dir}/${f}"
        else
            error "缺少 $f，请放入项目根目录"
            missing=true
        fi
    done

    if [ "$missing" = true ]; then
        exit 1
    fi

    ok "所有文件已就绪"
    ls -lh "${kernel_dir}/"
}

# ================================================================
# 运行构建
# ================================================================
run_build() {
    header "开始构建系统镜像"
    echo -e "  ${BOLD}系统类型:${NC}     ${SYSTEM_TYPE}"
    echo -e "  ${BOLD}内核版本:${NC}     ${KERNEL_VERSION}"
    [ -n "$DESKTOP_ENV" ]   && echo -e "  ${BOLD}桌面环境:${NC}     ${DESKTOP_ENV}"
    echo -e "  ${BOLD}构建工具:${NC}     ${BOOTSTRAP_TOOL}"
    echo -e "  ${BOLD}目标架构:${NC}     ${TARGET_ARCH}"
    [ -n "$DEBIAN_VERSION" ] && echo -e "  ${BOLD}Debian 版本:${NC}  ${DEBIAN_VERSION}"
    [ -n "$UBUNTU_VERSION" ] && echo -e "  ${BOLD}Ubuntu 版本:${NC}  ${UBUNTU_VERSION}"

    export BOOTSTRAP_TOOL
    export DEBIAN_VERSION
    export UBUNTU_VERSION
    export ARCH="${TARGET_ARCH}"

    chmod +x build.sh
    chmod +x scripts/*.sh

    sudo -E env \
        BOOTSTRAP_TOOL="$BOOTSTRAP_TOOL" \
        DEBIAN_VERSION="$DEBIAN_VERSION" \
        UBUNTU_VERSION="$UBUNTU_VERSION" \
        ARCH="$TARGET_ARCH" \
        ./build.sh "$SYSTEM_TYPE" "$KERNEL_VERSION" "$DESKTOP_ENV"
}

# ================================================================
# 主流程
# ================================================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   Xiaomi Raphael (K20 Pro) 本地镜像构建工具     ║${NC}"
    echo -e "${CYAN}║   目标架构: arm64 (aarch64)                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"

    # 如果没有参数，进入交互式选择
    if [ $# -eq 0 ]; then
        interactive_select
    else
        SYSTEM_TYPE="$1"
        KERNEL_VERSION="${2:-6.18}"
        DESKTOP_ENV="${3:-phosh-full}"

        if [[ "$SYSTEM_TYPE" == debian-* ]]; then
            DEBIAN_VERSION="${DEBIAN_VERSION:-trixie}"
            UBUNTU_VERSION=""
        elif [[ "$SYSTEM_TYPE" == ubuntu-* ]]; then
            UBUNTU_VERSION="${UBUNTU_VERSION:-jammy}"
            DEBIAN_VERSION=""
        fi
    fi

    check_architecture
    install_dependencies
    check_local_kernel
    run_build

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              构建成功完成!                       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    ls -lh rootfs.img 2>/dev/null || true
    ls -lh rootfs.7z 2>/dev/null || true
    echo ""
}

main "$@"
