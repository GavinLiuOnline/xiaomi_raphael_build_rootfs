# 小米 Raphael 设备 Linux 系统镜像构建项目

本项目为小米 Raphael（Redmi K20 Pro）专属 Linux 镜像构建项目，提供完整的 Debian / Ubuntu 系统镜像构建脚本与 GitHub Actions 自动化工作流，支持多内核、多桌面、服务器版，开箱即用，适配性完善。

## 📌 项目概述

项目集成全套自动化构建工具链，支持内核编译、系统镜像打包，覆盖桌面端与服务器端系统，所有镜像均预装适配设备的专属驱动、固件及常用工具，无需额外配置即可正常使用。

支持构建系统类型：

- **Debian 系列**：GNOME 桌面版、Phosh 移动桌面版、Server 无图形服务器版

- **Ubuntu 系列**：GNOME 桌面版、Phosh 移动桌面版、Server 无图形服务器版

- **定制内核**：编译适配设备 Linux 内核

## ✅ 设备适配状态

当前设备硬件适配完整，主流功能全部可用：

- 网络：2.4G/5G 双频 Wi-Fi、USB NCM 网络

- **蜂窝/基带**：SIM 卡识别、网络注册、**移动数据上网**（IPv4/IPv6）；开机插卡不再死机（崩溃隔离 + 匹配固件）

- 外设：蓝牙（文件传输/音频输出）、USB SSH/OTG 功能、触摸屏、手电筒（支持亮度调节）

- 基础硬件：屏幕显示、电池检测、实时时钟、GPU 渲染、FDE 加密

## 📊 版本支持矩阵

### 系统类型对照表

|系统标识|桌面环境|基础发行版|
|---|---|---|
|debian-server|无（纯命令行）|Debian|
|debian-gnome|GNOME|Debian|
|debian-phosh|Phosh 移动端桌面|Debian|
|ubuntu-server|无（纯命令行）|Ubuntu|
|ubuntu-gnome|GNOME|Ubuntu|
|ubuntu-phosh|Phosh 移动端桌面|Ubuntu|

### 系统与内核版本

- **Debian 版本**：trixie（默认最新）

- **Ubuntu 版本**：resolute（默认最新）

- **内核版本**：6.18、7.0（双版本可选）

### Phosh 桌面变体

- `phosh-core`：基础 Phosh 环境

- `phosh-full`：完整的 Phosh 环境

- `phosh-phone`：手机优化的 Phosh 环境

## 🚀 快速上手

### 方式一：下载预构建镜像

项目持续自动构建最新镜像，可直接前往 [Releases](https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/releases) 页面下载，无需本地编译。

> **⚠️ 大文件提示**：`ubuntu-gnome-6.18` / `ubuntu-gnome-7.0` 镜像体积超过 2GB，未上传至 Releases，需前往项目 Artifacts 下载。
> 
> 

### 方式二：GitHub Actions 自定义构建（推荐）

1. Fork 本仓库至个人 GitHub 账号

2. 进入仓库 **Actions** 页面，选择「构建系统镜像」工作流

3. 点击 **Run workflow**，自定义构建参数：
        

    - **构建模式**：`parallel`并行构建全部镜像（默认） / `single` 单独构建指定镜像

    - **系统类型**：支持多类型逗号分隔，默认全量构建

    - **内核版本**：支持 `7.0`（默认7.0可选6.18）

    - **构建工具**：`mmdebstrap`（默认） / `debootstrap`

    - **Phosh 变体**：仅 Phosh 桌面镜像生效，默认`phosh-core`

    - **系统版本**：默认 Debian: trixie、Ubuntu: resolute

4. 等待工作流执行完成，镜像自动打包发布至仓库 Releases

## 📦 镜像通用特性

### 全版本通用

- 默认配置**清华软件源**

- 预装简体中文语言包、中国标准时区，开箱汉化

- 支持 USB NCM 网络共享，电脑直连设备 SSH

- 内置 SSH 服务，支持 root / 普通用户远程登录

- **蜂窝基带开箱可用**：预装匹配的 modem 固件（00161）、内核 IPA 数据面修复、SIM 开机自动初始化、QRTR 版 ModemManager（QMAPv4，移动数据可用）；DNS 随移动数据自动使用运营商 DNS

- 支持**一键内核更新脚本**，可在线升级定制内核

- 默认账号密码：
       

    - 普通用户：`user` / `1234`

    - 超级用户：`root` / `1234`

- 设备默认 IP：`172.16.42.1`，SSH 连接命令：`ssh user@172.16.42.1`

### 桌面版专属特性

- GNOME / Phosh 双桌面环境可选，适配桌面、移动两种使用场景

- 已知问题：**GNOME 桌面电源键无法息屏**，后续版本持续修复

### 服务器版专属特性

- 内置网络管理器，支持有线、Wi-Fi、USB 多种联网方式

- 开机 15 秒自动熄屏，降低设备功耗

- 自定义快捷命令：`leijun` 关闭屏幕、`jinfan` 点亮屏幕

## 📶 移动数据 / 蜂窝网络使用

镜像已固化基带全套修复，刷机后插卡即可注册网络。出于功耗与误拨考虑，**移动数据默认不自动连接**，需手动开启：

```Plain Text
# 关闭 Wi-Fi（可选，确保走蜂窝）
sudo nmcli radio wifi off

# 连接移动数据（连接名以运营商为准，可用 nmcli connection show 查看）
sudo nmcli connection up CTNET

# 验证
ping -4 -c 3 www.baidu.com
```

> **说明**：
> - DNS 由 NetworkManager + systemd-resolved 按链路自动下发，连上后无需手动改 `resolv.conf`。
> - 若希望开机自动联网，可执行 `sudo nmcli connection modify <连接名> connection.autoconnect yes`。
> - 基带固化细节见 `基带测试/RAPHAEL-MODEM-STATUS.md`。

## ⬆️ 内核更新教程（只做内核调试用，非必要无需更新）

项目提供一键内核升级脚本，建议**root 权限**执行，快速更新设备定制内核：

官方原始链接：

```Plain Text
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/GengWei1997/kernel-deb/refs/heads/main/Update-kernel.sh)"
```

国内加速链接：

```Plain Text
sudo bash -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/GengWei1997/kernel-deb/refs/heads/main/ghproxy-Update-kernel.sh)"
```

脚本执行完成后，重启设备即可生效新内核。

## 🔧 设备安装教程

### 前置准备

1. 设备已完成 **Bootloader 解锁**

2. 在电脑上安装 `adb`、`fastboot` 刷机工具，并配置环境变量

3. 解压下载的 `.7z` 镜像压缩包，获取 `rootfs.img`、`xiaomi-k20pro-boot.img` 下载[u-boot.img](https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/releases/tag/v1.0.0)（选择最近日期版本）

### 刷机命令

```Plain Text
# 1. 进入 Fastboot 模式
adb reboot bootloader

# 2. 擦除分区
fastboot erase dtbo
fastboot erase boot
fastboot erase cache
fastboot erase userdata

# 3. 刷入 boot 镜像
fastboot flash cache xiaomi-k20pro-boot.img
fastboot flash boot u-boot.img

# 4. 刷入系统镜像（需要先解压 rootfs.7z）
fastboot flash userdata rootfs.img

# 5. 重启设备
fastboot reboot
```

### Recovery 卡刷（`.zip` 卡刷包）

Release 里发布的 `.zip` 卡刷包已整合 u-boot(boot)、内核(cache.img)、根文件系统(system.img) 和 logo，可在第三方 Recovery（TWRP/OrangeFox）中一次刷入，无需逐个 fastboot。

**第一步：合并分卷（仅当卡刷包被拆分为 `*.partXX` 时）**

超过 GitHub Release 单文件 2GB 限制的卡刷包会被拆分成 `xxx.zip.part00`、`xxx.zip.part01` … 必须下载**同一个包的全部分卷**、放在同一目录里合并成完整 `.zip` 后才能刷入：

```bash
# Linux / macOS：按顺序合并所有分卷
cat 文件名.zip.part* > 文件名.zip
# 校验：输出应与 Release 页面给出的 SHA256 一致
sha256sum 文件名.zip
```

```bat
:: Windows (CMD)：按顺序拼接
copy /b 文件名.zip.part00 + 文件名.zip.part01 + 文件名.zip.part02 文件名.zip
```

> 未被拆分的卡刷包直接用，跳过此步。合并后 SHA256 对不上说明分卷不全或下载损坏，重新下载，切勿刷入。

**第二步：刷入卡刷包（任选一种）**

先让设备进入第三方 Recovery，然后：

- **方式 A — adb sideload（推荐，不占用手机存储）**

```bash
# 在 Recovery 中进入「高级」→「ADB Sideload」并滑动开始，然后在电脑执行：
adb sideload 文件名.zip
```

- **方式 B — Recovery 本地安装**：将完整 `.zip` 拷到设备，在 Recovery「安装」中选中该 `.zip` 滑动确认。

> ⚠️ **不要把卡刷包放在「内置存储」里刷入！** 卡刷会写入并格式化 userdata（内置存储），放在内置存储上的包会在刷入过程中被清除而导致失败。请使用 **外置 SD 卡** 存放卡刷包，或使用 **adb sideload**（从电脑传入，不占用内置存储）。

## ❓ 常见问题 FAQ

- **开机卡死 / 插卡死机**：已修复。匹配固件（00161）+ 内核 IPA 数据面修复 + modem 崩溃隔离后，插卡开机不再死机。若仍异常，请确认刷的是最新镜像。

- **移动数据连上但 ping 域名失败（IP 能通）**：DNS 问题。新镜像已固定使用公共 DNS（`223.5.5.5` / `114.114.114.114`），不跟随运营商下发，`/etc/resolv.conf` 为静态文件、NetworkManager 不再接管（`dns=none`）。旧镜像可手动把这两个 nameserver 写入 `/etc/resolv.conf`。

- **Windows 无法连接设备 CDC NCM 驱动**：参考解决方案视频[BV1tW4y1A79V](https://www.bilibili.com/video/BV1tW4y1A79V/)

- **Server 版如何联网**：
        

    1. OTG 外接网线，系统自动识别联网

    2. OTG 外接键盘，终端输入 `nmtui` 可视化连接 Wi-Fi

    3. USB 连接电脑，安装 NCM 驱动后，通过 `nmtui` 配置网络

## 🙏 致谢

本项目基于众多开源项目与开发者成果开发，特此致谢：

- Linux 内核官方开发团队、Debian / Ubuntu 开源社区、Phosh 桌面开发团队

- [@璀璨梦星](https://github.com/ccmx200)：项目优化与创新思路支持

- [@map220v](https://github.com/map220v/ubuntu-xiaomi-nabu)：上游项目参考

- [@Pc1598](https://github.com/Pc1598)：sm8150-mainline-raphael 设备内核维护

- [Aospa\-raphael\-unofficial/linux](https://github.com/Aospa-raphael-unofficial/linux)、[sm8150\-mainline/linux](https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux)：内核源码支持

- 所有开源贡献者与项目使用者
