#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
DEB_OUT_DIR="${DEB_OUT_DIR:-$SCRIPT_DIR/../debs}"

. "$CONFIG_DIR/build-config.sh"

SYSTEM_TYPE="${SYSTEM_TYPE:-ubuntu-server}"
DESKTOP_ENV="${DESKTOP_ENV:-}"
DEBIAN_VERSION="${DEBIAN_VERSION:-trixie}"
UBUNTU_VERSION="${UBUNTU_VERSION:-resolute}"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06] 📦 安装软件包"

export DEBIAN_FRONTEND=noninteractive

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 更新系统包..."
chroot rootdir apt-get update
chroot rootdir apt-get upgrade -y

BASE_PACKAGES="bash-completion sudo apt-utils ssh openssh-server nano gpgv gnupg gpgv2 grub2-common ca-certificates kmod debconf wireless-regdb less procps psmisc iputils-ping systemd udev dbus net-tools rfkill wireless-tools network-manager initramfs-tools chrony curl wget locales tzdata iproute2 zram-tools"

if [[ "$SYSTEM_TYPE" == *"debian-"* ]]; then 
   BASE_PACKAGES="bash-completion sudo apt-utils ssh openssh-server nano network-manager systemd-boot initramfs-tools chrony curl wget locales tzdata fonts-wqy-microhei dnsmasq iptables iproute2 zram-tools udev dbus kmod ca-certificates wireless-regdb"
elif [[ "$SYSTEM_TYPE" == *"ubuntu-"* ]]; then
	if [[ "$SYSTEM_TYPE" == *"server"* ]]; then
		BASE_PACKAGES="bash-completion sudo apt-utils ssh openssh-server nano network-manager net-tools initramfs-tools chrony curl wget locales tzdata dnsmasq iptables iproute2 zram-tools udev dbus kmod ca-certificates wireless-regdb"
	else
		BASE_PACKAGES="bash-completion sudo apt-utils ssh openssh-server nano network-manager firefox net-tools grub-efi-arm64-signed initramfs-tools chrony curl wget locales tzdata dnsmasq iptables iproute2 zram-tools udev dbus kmod ca-certificates wireless-regdb"
	fi
fi

# 通用外设 + Qualcomm 运行时依赖（Jammy 源中可安装的）
DEVICE_PACKAGES="wpasupplicant iw iproute2 alsa-ucm-conf alsa-utils power-profiles-daemon gpsd gpsd-clients libmbim-utils liblzma5"


if [[ "$SYSTEM_TYPE" != *"server"* ]]; then
    case "$DESKTOP_ENV" in
        "gnome")
            if [[ "$SYSTEM_TYPE" == *"ubuntu-"* ]]; then
                DESKTOP_PACKAGES="ubuntu-desktop"
            elif [[ "$SYSTEM_TYPE" == *"debian-"* ]]; then
                DESKTOP_PACKAGES="gnome"
            fi
            ;;
        "phosh-core")
            DESKTOP_PACKAGES="phosh-core"
            ;;
        "phosh-full")
            DESKTOP_PACKAGES="phosh-full"
            ;;
        "phosh-phone")
            DESKTOP_PACKAGES="phosh-phone"
            ;;
        *)
            DESKTOP_PACKAGES=""
            ;;
    esac
else
    DESKTOP_PACKAGES=""
fi

# Plymouth provides the vendor boot-logo animation (script.so plugin, drm /
# frame-buffer renderers and the initramfs hook). Installed for every variant
# (incl. server) so the splash works; the theme itself is set up in
# 08b-config-plymouth.sh before the initramfs is generated in 09.
PLYMOUTH_PACKAGES="plymouth plymouth-themes plymouth-label"

ALL_PACKAGES="$BASE_PACKAGES $DEVICE_PACKAGES $DESKTOP_PACKAGES $PLYMOUTH_PACKAGES"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 基础包: $(echo "$BASE_PACKAGES" | tr ' ' ', ')"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 设备包: $(echo "$DEVICE_PACKAGES" | tr ' ' ', ')"
if [ -n "$DESKTOP_PACKAGES" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 桌面包: $(echo "$DESKTOP_PACKAGES" | tr ' ' ', ')"
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 开始安装（这可能需要几分钟...）"
chroot rootdir apt-get install -y $ALL_PACKAGES
if [[ "$SYSTEM_TYPE" == *"debian-"* ]]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 修复 Debian dpkg 错误"
    chroot rootdir dpkg --remove --force-remove-reinstreq shim-signed 2>/dev/null || true
    chroot rootdir dpkg --purge shim-signed 2>/dev/null || true
    chroot rootdir dpkg --configure -a 2>/dev/null || true
    chroot rootdir apt-get -f install -y 2>/dev/null || true
fi

install_qcom_local_debs() {
	local deb_dir="$1"
	local required=(
		libqrtr1_*_arm64.deb
		qrtr-tools_*_arm64.deb
		rmtfs_*_arm64.deb
		protection-domain-mapper_*_arm64.deb
		tqftpserv_*_arm64.deb
		audioreach-topology_*_all.deb
		modemmanager-qrtr-sm8150_*_jammy_arm64.deb
	)

	if [ ! -d "$deb_dir" ]; then
		echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06] ❌ deb 目录不存在: $deb_dir" >&2
		echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]    请先运行: $SCRIPT_DIR/docker-build.sh" >&2
		exit 1
	fi

	local missing=0
	for pattern in "${required[@]}"; do
		if ! compgen -G "$deb_dir/$pattern" >/dev/null; then
			echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06] ❌ 缺少: $deb_dir/$pattern" >&2
			missing=1
		fi
	done
	if [ "$missing" -ne 0 ]; then
		exit 1
	fi

	local mm_deb
	mm_deb="$(ls -1 "$deb_dir"/modemmanager-qrtr-sm8150_*_jammy_arm64.deb 2>/dev/null | sort -V | tail -1)"
	if [ -z "$mm_deb" ]; then
		echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06] ❌ 缺少: $deb_dir/modemmanager-qrtr-sm8150_*_jammy_arm64.deb" >&2
		echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]    请先运行: $SCRIPT_DIR/build-modemmanager-deb.sh" >&2
		exit 1
	fi
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ ModemManager: $(basename "$mm_deb") (QMAPv4 patch, 禁用 v5)"

chroot rootdir sh -c "apt-get remove -y --allow-remove-essential \
	modemmanager libqmi-utils libqmi-proxy libqmi-glib5"
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 安装本地 Qualcomm deb: $deb_dir"
	mkdir -p rootdir/tmp/qcom-debs
	# 按依赖顺序：libqrtr1 -> tools/rmtfs/pd-mapper/tqftpserv -> topology -> MM
	cp "$deb_dir"/libqrtr1_*_arm64.deb rootdir/tmp/qcom-debs/
	cp "$deb_dir"/qrtr-tools_*_arm64.deb \
		"$deb_dir"/rmtfs_*_arm64.deb \
		"$deb_dir"/protection-domain-mapper_*_arm64.deb \
		"$deb_dir"/tqftpserv_*_arm64.deb \
		"$deb_dir"/audioreach-topology_*_all.deb \
		rootdir/tmp/qcom-debs/
	cp "$mm_deb" rootdir/tmp/qcom-debs/

	chroot rootdir sh -c "dpkg -i /tmp/qcom-debs/libqrtr1_*_arm64.deb"
	chroot rootdir sh -c "dpkg -i /tmp/qcom-debs/qrtr-tools_*_arm64.deb \
		/tmp/qcom-debs/rmtfs_*_arm64.deb \
		/tmp/qcom-debs/protection-domain-mapper_*_arm64.deb \
		/tmp/qcom-debs/tqftpserv_*_arm64.deb"
	chroot rootdir sh -c '
		export DEBIAN_FRONTEND=noninteractive
		dpkg -i --auto-deconfigure /tmp/qcom-debs/modemmanager-qrtr-sm8150_*.deb
		apt-get install -f -y
	'
	chroot rootdir sh -c "dpkg -i /tmp/qcom-debs/audioreach-topology_*_all.deb"
	chroot rootdir apt-get install -f -y
	rm -rf rootdir/tmp/qcom-debs

	mkdir -p rootdir/var/lib/rmtfs

	# qrtr-ns 在 lib/systemd/system；rmtfs/pd-mapper 在 usr/lib/systemd/system
	chroot rootdir systemctl enable qrtr-ns.service
	chroot rootdir systemctl disable rmtfs-dir.service 2>/dev/null || true
	chroot rootdir systemctl mask rmtfs-dir.service 2>/dev/null || true
	chroot rootdir systemctl unmask rmtfs.service 2>/dev/null || true
	#chroot rootdir systemctl enable rmtfs-dir.service pd-mapper.service tqftpserv.service
	chroot rootdir systemctl enable rmtfs.service pd-mapper.service tqftpserv.service
	# 避免与 rmtfs 主服务竞态（与 Debian 打包策略一致）

}

install_qcom_local_debs "$DEB_OUT_DIR"


# 修改服务配置
if [[ "$SYSTEM_TYPE" == *"debian-"* ]]; then
    sed -i '/ConditionKernelVersion/d' rootdir/lib/systemd/system/pd-mapper.service 2>/dev/null || true
fi

if [[ "$SYSTEM_TYPE" != *"server"* ]]; then
    if [ "$DESKTOP_ENV" = "gnome" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 配置 GDM 自动登录"
        cat > rootdir/etc/gdm3/custom.conf << 'EOF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=user
EOF
		chroot rootdir systemctl disable brltty.service
		chroot rootdir systemctl mask brltty.service
        #chroot rootdir gsettings set org.gnome.mutter auto-rotate-screen true || true
    fi
fi

if [ -f "alsa-xiaomi-raphael.deb" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 安装 ALSA 配置"
    cp alsa-xiaomi-raphael.deb rootdir/tmp/
    chroot rootdir dpkg -i /tmp/alsa-xiaomi-raphael.deb
    rm rootdir/tmp/alsa-xiaomi-raphael.deb
fi

# ================================================================
# 音频：统一使用 PipeWire（Ubuntu 24.04 Noble 的默认音频栈）
# ----------------------------------------------------------------
# 切勿用 PulseAudio 去“替换” PipeWire！pipewire-pulse / pipewire-audio
# 是 ubuntu-desktop / gnome-shell / gdm3 的硬依赖，purge 它们再 autoremove
# 会级联卸载整个 GNOME 桌面，导致开机黑屏（实测踩过坑）。
# PipeWire 自带 pipewire-pulse 提供 PulseAudio 兼容层，应用无需改动。
# ================================================================
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 配置 PipeWire 作为音频服务"

# 确保 PipeWire 全套及兼容层安装齐全（不卸载任何东西）
chroot rootdir apt-get install -y --no-install-recommends \
    pipewire pipewire-pulse pipewire-audio pipewire-alsa wireplumber \
    2>/dev/null || true

# 解除任何历史遗留的屏蔽，并启用 PipeWire 用户服务
chroot rootdir systemctl --global unmask \
    pipewire.socket pipewire-pulse.socket pipewire.service \
    pipewire-pulse.service wireplumber.service 2>/dev/null || true
chroot rootdir systemctl --global enable \
    pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true

if [[ "$SYSTEM_TYPE" != *"server"* ]]; then
    if [[ "$DESKTOP_ENV" == phosh* ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06]   └─ 启用 Phosh 服务"
        chroot rootdir systemctl enable phosh
    fi
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [06] ✅ 软件包安装完成"
