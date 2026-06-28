#!/bin/bash
set -e

HOSTNAME="${HOSTNAME:-xiaomi-raphael}"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [04] 🌐 配置网络和主机名"

# DNS：固定使用公共 DNS，不跟随运营商下发。
# 运营商（移动数据）下发的 DNS 时常不可达/解析异常，导致 ping 域名失败；
# 这里写死国内可达的公共 DNS，并在 10b 让 NetworkManager 不接管 resolv.conf
# （dns=none），保证无论走移动数据还是 WiFi 都用同一套公共 DNS。
rm -f rootdir/etc/resolv.conf
cat > rootdir/etc/resolv.conf << 'EOF'
# 公共 DNS（固定，不随链路变化）。修改请同步 10b-config-modem.sh。
nameserver 223.5.5.5
nameserver 114.114.114.114
EOF

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [04]   └─ 主机名: ${HOSTNAME}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] [04]   └─ DNS: 公共 223.5.5.5 / 114.114.114.114 (固定, 见 10b)"

echo "${HOSTNAME}" > rootdir/etc/hostname
echo "127.0.0.1 localhost
127.0.1.1 ${HOSTNAME}" > rootdir/etc/hosts

echo "[$(date +'%Y-%m-%d %H:%M:%S')] [04] ✅ 网络配置完成"