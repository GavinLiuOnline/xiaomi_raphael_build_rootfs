# 小米 Raphael（Redmi K20 Pro）Linux 系统镜像构建项目

为小米 Raphael（Redmi K20 Pro / SM8150）打造的一套 Linux 镜像构建工具链，提供完整的 Debian / Ubuntu 镜像构建脚本与 GitHub Actions 自动化工作流，产出开箱即用的卡刷包。

---

## 1. 项目目的

把"主线 Linux 跑在 K20 Pro 上"这件事**工程化、可复现**：

- **一键产出可刷机的系统镜像**：内核、设备固件、根文件系统、引导（u-boot）全部打包进一个 Recovery 卡刷包，刷入即用，不需要使用者再手动拼装。
- **固化设备适配与基带修复**：把零散的驱动、固件、内核补丁、开机初始化逻辑全部沉淀到构建脚本里，每次构建都自带这些修复，避免"换台机器/重装就丢"。
- **多系统多内核可选**：Debian / Ubuntu × Server / GNOME / Phosh × 多内核版本，按需构建。
- **本地与云端两种构建方式**：既能 Fork 后用 GitHub Actions 云端构建，也能在本地一条命令构建。

### 设备适配状态

当前硬件适配较为完整，主流功能均可用：

- **网络**：2.4G/5G 双频 Wi-Fi、USB NCM 网络共享
- **蜂窝 / 基带**：SIM 卡识别、网络注册、**移动数据上网（IPv4/IPv6）**；开机插卡不再死机（modem 崩溃隔离 + 匹配固件 00161 + 内核 IPA 数据面修复）
- **外设**：蓝牙（文件传输 / 音频输出）、USB SSH/OTG、触摸屏、手电筒（含亮度调节）
- **基础硬件**：屏幕显示、电池检测、实时时钟、GPU 渲染、FDE 加密、PipeWire 音频

---

## 2. 如何使用产物

### 2.1 获取镜像

前往本仓库 [Releases](https://github.com/GavinLiuOnline/xiaomi_raphael_build_rootfs/releases) 下载对应机型的 `.zip` 卡刷包，无需本地编译。卡刷包内已整合 **u-boot(boot) + 内核(cache.img) + 根文件系统(system.img) + logo**。

> 体积超过 GitHub Release 单文件 2GB 限制的镜像（如部分 `ubuntu-gnome` 镜像）会被拆分为 `*.partXX` 分卷，或仅保留在 Actions 的 Artifacts 中。

#### 系统类型对照

| 系统标识 | 桌面环境 | 基础发行版 |
|---|---|---|
| debian-server | 无（纯命令行） | Debian |
| debian-gnome | GNOME | Debian |
| debian-phosh | Phosh 移动端桌面 | Debian |
| ubuntu-server | 无（纯命令行） | Ubuntu |
| ubuntu-gnome | GNOME | Ubuntu |
| ubuntu-phosh | Phosh 移动端桌面 | Ubuntu |

### 2.2 前置准备

1. 设备已完成 **Bootloader 解锁**。
2. 电脑安装好 `adb`、`fastboot`，并配置环境变量。
3. 已刷入第三方 Recovery（TWRP / OrangeFox）——卡刷方式需要。

### 2.3 合并分卷（仅当下载到 `*.partXX` 时）

被拆分的卡刷包必须下载**同一个包的全部分卷**、放在同一目录里合并成完整 `.zip` 后才能刷入：

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

> 未被拆分的卡刷包跳过此步。合并后 SHA256 对不上 = 分卷不全或下载损坏，请重新下载，**切勿刷入**。

### 2.4 刷机

#### 方式 A：Recovery 卡刷（推荐，使用 Release 的 `.zip`）

进入第三方 Recovery 后，任选一种：

- **A1 — adb sideload（最推荐，不占用手机存储）**

```bash
# 在 Recovery 中进入「高级」→「ADB Sideload」并滑动开始，然后在电脑执行：
adb sideload 文件名.zip
```

- **A2 — Recovery 本地安装**：将完整 `.zip` 拷到**外置 SD 卡**，在 Recovery「安装」中选中该 `.zip` 滑动确认。

> ⚠️ **不要把卡刷包放在「内置存储」里刷入！** 卡刷会写入并格式化 userdata（内置存储），放在内置存储上的包会在刷入过程中被清除而导致失败。请使用 **外置 SD 卡** 存放，或用 **adb sideload**（从电脑传入，不占用内置存储）。

#### 方式 B：fastboot 手动刷入（使用 `.7z` 内的 `rootfs.img`）

适用于自行解压镜像、单独刷各分区。需额外下载 [u-boot.img](https://github.com/GengWei1997/linux-xiaomi-raphael-uboot/releases/tag/v1.0.0)（选最近日期版本）。

```bash
# 1. 进入 Fastboot 模式
adb reboot bootloader

# 2. 擦除分区
fastboot erase dtbo
fastboot erase boot
fastboot erase cache
fastboot erase userdata

# 3. 刷入引导与内核
fastboot flash cache xiaomi-k20pro-boot.img
fastboot flash boot u-boot.img

# 4. 刷入系统镜像（需先解压 rootfs.7z 得到 rootfs.img）
fastboot flash userdata rootfs.img

# 5. 重启设备
fastboot reboot
```

### 2.5 首次登录与联网

- **默认账号**：普通用户 `user` / `1234`，超级用户 `root` / `1234`
- **USB 直连 SSH**：设备默认 IP `172.16.42.1`，连接命令 `ssh user@172.16.42.1`
- **Server 版联网**：① OTG 外接网线自动识别；② OTG 外接键盘后终端 `nmtui` 连 Wi-Fi；③ USB 连电脑装 NCM 驱动后用 `nmtui` 配置

#### 使用移动数据

镜像已固化基带修复，插卡即可注册网络。出于功耗与误拨考虑，**移动数据默认不自动连接**，需手动开启：

```bash
# 关闭 Wi-Fi（可选，确保走蜂窝）
sudo nmcli radio wifi off

# 连接移动数据（连接名以运营商为准，可用 nmcli connection show 查看）
sudo nmcli connection up CTNET

# 验证
ping -4 -c 3 www.baidu.com
```

> DNS 已固定使用公共 DNS（`223.5.5.5` / `114.114.114.114`），不跟随运营商下发，连上即可解析域名。如需开机自动联网：`sudo nmcli connection modify <连接名> connection.autoconnect yes`。

### 2.6 镜像通用特性

- 默认配置**清华软件源**，预装简体中文语言包与中国标准时区，开箱汉化
- 内置 SSH 服务，支持 root / 普通用户远程登录；支持 USB NCM 网络共享
- **蜂窝基带开箱可用**：匹配 modem 固件（00161）+ 内核 IPA 数据面修复 + SIM 开机自动初始化 + QRTR 版 ModemManager（QMAPv4）
- 音频统一使用 **PipeWire**（含 `pipewire-audio`，保证音频正常）
- 桌面版提供 GNOME / Phosh 双环境；服务器版开机 15 秒自动熄屏，自定义快捷命令 `leijun`（关屏）/ `jinfan`（点亮）

---

## 3. 如何下载源码构建 / Fork 构建

### 方式一：Fork + GitHub Actions 云端构建（推荐，无需本地环境）

1. **Fork** 本仓库到个人 GitHub 账号。
2. 进入仓库 **Actions** 页面，选择「构建系统镜像」工作流。
3. 点击 **Run workflow**，按需自定义参数：
   - **构建模式**：`parallel` 并行构建全部（默认）/ `single` 单独构建指定镜像
   - **系统类型**：多类型用逗号分隔，默认全量
   - **内核版本**：`7.0`（默认）/ `6.18`
   - **构建工具**：`mmdebstrap`（默认）/ `debootstrap`
   - **Phosh 变体**：仅 Phosh 镜像生效，`phosh-core`（默认）/ `phosh-full` / `phosh-phone`
   - **系统版本**：Debian 默认 `trixie`，Ubuntu 默认 `jammy`
4. 工作流执行完成后，镜像自动打包发布到你 Fork 仓库的 **Releases**（大文件自动拆分为分卷）。

### 方式二：本地构建

适用于任何架构主机，目标始终为 arm64；x86_64 主机会自动用 `qemu-user-static` 跨架构编译。

```bash
# 1. 克隆源码
git clone https://github.com/GavinLiuOnline/xiaomi_raphael_build_rootfs.git
cd xiaomi_raphael_build_rootfs

# 2a. 交互式选择（推荐，按提示选系统/版本/内核）
sudo ./local-build.sh

# 2b. 或直接传参：<系统类型> [内核版本] [桌面环境]
sudo ./local-build.sh ubuntu-phosh 6.18 phosh-full
sudo ./local-build.sh debian-server 7.0
```

`local-build.sh` 会自动安装依赖（`mmdebstrap`/`debootstrap`、`p7zip`、`zip`、`qemu-user-static` 等）、下载内核包与 `boot.img`，再调用 `build.sh` 完成构建。产物为 `rootfs.img` / `rootfs.7z` 及卡刷包 `.zip`。

> 构建所需的内核 deb（`linux-image` / `linux-headers` / `firmware` / `alsa`）默认从内核仓库 Release 下载；也可手动放到项目根目录后离线构建。

### 内核单独更新（仅调试用，非必要无需更新）

设备上可一键升级定制内核（建议 root）：

```bash
# 官方原始链接
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/GengWei1997/kernel-deb/refs/heads/main/Update-kernel.sh)"

# 国内加速链接
sudo bash -c "$(curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/GengWei1997/kernel-deb/refs/heads/main/ghproxy-Update-kernel.sh)"
```

执行完成后重启设备即可生效。

---

## 4. 注意事项

- ⚠️ **卡刷包切勿放在内置存储刷入**：刷机会格式化 userdata（内置存储），放在内置存储上的包会被清除导致失败。请用**外置 SD 卡**或 **adb sideload**。
- **分卷必须先合并再刷**：`*.partXX` 要下齐、合并成完整 `.zip` 并核对 SHA256 后才能刷入。
- **刷机有风险**：会擦除 `userdata` 等分区，请提前备份重要数据；务必确认 Bootloader 已解锁。
- **移动数据默认不自动连接**：需手动 `nmcli connection up <连接名>`，详见 2.5。
- **音频依赖 PipeWire**：镜像强制安装 `pipewire-audio`，请勿手动卸载 PipeWire 组件（`pipewire-pulse`/`pipewire-audio` 是桌面硬依赖，purge 会级联卸载整个 GNOME 桌面导致黑屏）。
- **Windows 连不上设备 CDC NCM**：参考解决方案视频 [BV1tW4y1A79V](https://www.bilibili.com/video/BV1tW4y1A79V/)。
- 基带固化细节见 `基带测试/RAPHAEL-MODEM-STATUS.md`。

---

## 5. 已知问题

- **GNOME 桌面电源键无法息屏**：后续版本持续修复。
- **大体积镜像不直接发 Release**：部分 `ubuntu-gnome` 镜像超过 2GB，会被拆分为分卷，或仅保留在 Actions Artifacts。
- **移动数据 ping 域名失败（旧镜像）**：旧镜像 DNS 跟随运营商下发可能不可达；新镜像已固定公共 DNS。旧镜像可手动把 `nameserver 223.5.5.5` / `nameserver 114.114.114.114` 写入 `/etc/resolv.conf`。
- **RF/modem 稳定性**：当前以"崩溃隔离"为安全网（modem 崩溃不拖垮整机），根因层面的 RF 稳定性仍在跟进。

---

## 6. 鸣谢

本项目基于众多开源项目与开发者成果，特此致谢：

- Linux 内核官方开发团队、Debian / Ubuntu 开源社区、Phosh 桌面开发团队
- [@璀璨梦星](https://github.com/ccmx200)：项目优化与创新思路支持
- [@map220v](https://github.com/map220v/ubuntu-xiaomi-nabu)：上游项目参考
- [@Pc1598](https://github.com/Pc1598)：sm8150-mainline-raphael 设备内核维护
- [Aospa-raphael-unofficial/linux](https://github.com/Aospa-raphael-unofficial/linux)、[sm8150-mainline/linux](https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux)：内核源码支持
- 所有开源贡献者与项目使用者
