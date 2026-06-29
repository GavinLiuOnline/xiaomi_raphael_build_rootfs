#!/bin/bash
set -e

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [10] 📱 配置 USB NCM 网络"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [10]   └─ 创建 dnsmasq 配置"

# 手机 usb0 固定 172.16.42.1；电脑走 DHCP 自动分配 172.16.42.2–254
cat > rootdir/etc/dnsmasq.d/usb-ncm.conf << 'EOF'
interface=usb0
bind-dynamic
port=0
dhcp-authoritative
log-dhcp
dhcp-range=172.16.42.2,172.16.42.254,255.255.255.0,12h
dhcp-option=3,172.16.42.1
dhcp-option=6,223.5.5.5,114.114.114.114
EOF
# 可选：按电脑 MAC 绑定固定 IP，取消注释并改成实际 MAC
cat > rootdir/etc/dnsmasq.d/usb-ncm-hosts.conf << 'EOF'
# 示例：让某台电脑永远拿到 172.16.42.2
# dhcp-host=2e:dc:b4:8b:6c:1f,172.16.42.2
EOF
echo "net.ipv4.ip_forward=1" | tee rootdir/etc/sysctl.d/99-usb-ncm.conf
chroot rootdir systemctl enable dnsmasq

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [10]   └─ 配置 NetworkManager 托管 usb0"
install -d rootdir/etc/NetworkManager/conf.d
cat > rootdir/etc/NetworkManager/conf.d/raphael-usb-ncm.conf << 'EOF'
[keyfile]
# Ubuntu 默认只托管 wifi/gsm，显式纳入 usb0 (USB NCM)
unmanaged-devices=*,except:type:wifi,except:type:gsm,except:type:cdma,except:interface-name:usb0
EOF
install -d rootdir/etc/NetworkManager/system-connections
cat > rootdir/etc/NetworkManager/system-connections/USB-NCM.nmconnection << 'EOF'
[connection]
id=USB-NCM
uuid=a3b8c4d2-1e5f-4a6b-9c0d-e5f6a7b8c9d0
type=ethernet
interface-name=usb0
autoconnect=yes
autoconnect-priority=100

[ethernet]

[ipv4]
method=manual
address1=172.16.42.1/24
never-default=true

[ipv6]
method=ignore
EOF
chmod 600 rootdir/etc/NetworkManager/system-connections/USB-NCM.nmconnection

cat > rootdir/usr/local/sbin/setup-usb-ncm.sh << 'EOF'
#!/bin/sh
set -e
modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
G=/sys/kernel/config/usb_gadget/g1
if [ ! -d "$G" ]; then
	mkdir -p $G
	echo 0x1d6b > $G/idVendor
	echo 0x0104 > $G/idProduct
	echo 0x0200 > $G/bcdUSB
	mkdir -p $G/strings/0x409
	echo xiaomi-raphael > $G/strings/0x409/manufacturer
	echo NCM > $G/strings/0x409/product
	echo $(cat /etc/machine-id) > $G/strings/0x409/serialnumber
	mkdir -p $G/configs/c.1
	mkdir -p $G/configs/c.1/strings/0x409
	echo NCM > $G/configs/c.1/strings/0x409/configuration
	mkdir -p $G/functions/ncm.usb0
	ln -sf $G/functions/ncm.usb0 $G/configs/c.1/
fi

# 等待 UDC 就绪（开机时 dwc3 可能尚未注册）
i=0
UDC=
while [ $i -lt 30 ]; do
	UDC=$(ls /sys/class/udc 2>/dev/null | head -n 1)
	[ -n "$UDC" ] && break
	i=$((i + 1))
	sleep 1
done
[ -n "$UDC" ] || { echo "setup-usb-ncm: no UDC found" >&2; exit 1; }

# UDC 文件可能只有换行符，不能仅用 -s 判断是否已绑定
current=$(tr -d '\n' < "$G/UDC" 2>/dev/null || true)
if [ "$current" != "$UDC" ]; then
	[ -n "$current" ] && echo > "$G/UDC" 2>/dev/null || true
	echo "$UDC" > "$G/UDC"
fi

# 等待 usb0 网卡出现
i=0
while [ $i -lt 10 ]; do
	ip link show usb0 >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.5
done

nmcli device set usb0 managed yes 2>/dev/null || true
nmcli connection up USB-NCM 2>/dev/null || true
OUT=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
sysctl -w net.ipv4.ip_forward=1
if [ -n "$OUT" ] && [ "$OUT" != "lo" ]; then
	iptables -t nat -C POSTROUTING -o "$OUT" -j MASQUERADE 2>/dev/null || \
		iptables -t nat -A POSTROUTING -o "$OUT" -j MASQUERADE
	iptables -C FORWARD -i "$OUT" -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
		iptables -A FORWARD -i "$OUT" -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT
	iptables -C FORWARD -i usb0 -o "$OUT" -j ACCEPT 2>/dev/null || \
		iptables -A FORWARD -i usb0 -o "$OUT" -j ACCEPT
fi
systemctl restart dnsmasq || true
EOF
chmod +x rootdir/usr/local/sbin/setup-usb-ncm.sh
cat > rootdir/etc/systemd/system/usb-ncm.service << 'EOF'
[Unit]
Description=USB CDC-NCM gadget setup
After=NetworkManager.service
Wants=NetworkManager.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/setup-usb-ncm.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [10]   └─ 启用 usb-ncm 服务"
chroot rootdir systemctl enable usb-ncm

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [10] ✅ USB NCM 配置完成"
