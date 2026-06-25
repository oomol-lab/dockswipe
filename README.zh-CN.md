# dockswipe

[English](./README.md) · [简体中文](./README.zh-CN.md)

[![CI](https://img.shields.io/github/actions/workflow/status/oomol-lab/dockswipe/ci.yml?branch=main&label=CI&logo=github)](https://github.com/oomol-lab/dockswipe/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/oomol-lab/dockswipe?logo=github&color=blue)](https://github.com/oomol-lab/dockswipe/releases/latest)
[![Homebrew](https://img.shields.io/badge/homebrew-oomol--lab%2Ftap-orange?logo=homebrew)](https://github.com/oomol-lab/homebrew-tap)
[![Platform](https://img.shields.io/badge/platform-macOS-black?logo=apple)](https://www.apple.com/macos/)
[![Language](https://img.shields.io/badge/language-Objective--C-438eff)](./dockswipe.m)
[![License](https://img.shields.io/github/license/oomol-lab/dockswipe?color=green)](./LICENSE)

从命令行合成 macOS **触控板 dock-swipe 手势**——以**真正的触控板手势路径**（不是快捷键、也不是瞬切 API）
可编程地触发 **Mission Control**、**切换桌面（Spaces）**、**App Exposé**、**显示桌面**、**Launchpad**，
并且**可控制速率**（跟手的渐进动画，而非瞬间完成）。

为**端到端 UI 自动化测试**而生：它驱动的正是三/四指触控板 swipe 在系统层产生的效果，
既不靠快捷键，也不需要真实触控板。

## 演示

直接从命令行驱动 macOS dock-swipe 手势：

<p align="center">
  <video src="https://github.com/user-attachments/assets/056b10fe-ecaa-4716-8f5d-a01eaf0d4400" controls width="100%"></video>
</p>

## 为什么不用快捷键 / Spaces API？

| 需求 | dock-swipe 为什么对得上 |
| --- | --- |
| **要触控板路径，不要快捷键** | 这些事件**就是** macOS 把三/四指 swipe 传给 Dock/WindowServer 的方式。`Ctrl+↑` / `Ctrl+←→` 是另一条路；而直接切桌面的 API（`CGSManagedDisplaySetCurrentSpace`、Hammerspoon `hs.spaces`）**根本打不开 Mission Control**，只有手势路径能。 |
| **要控制速率** | 事件带一个连续的 `progress` 进度值 + `began → changed → ended` 相位。发一串进度递进的帧 + 帧间 sleep，动画就**跟手**展开。 |
| **框架无关** | 效果是系统全局（Dock/WindowServer），不存在按 App 识别的问题（不会"Safari 行、Chrome 不行"）。 |

## 工作原理

macOS 把触控板三/四指 swipe 在 Dock/WindowServer 层编码成一个未公开的「dock swipe」`CGEvent`。
`dockswipe` 用私有字段布局构造该事件，再用 `CGEventPost` 注入：

- 每步两个事件——一个伴随的 `NSEventTypeGesture`（type 29）marker + 主 dock-control 事件
  （type 30），后者带子类型 `kIOHIDEventTypeDockSwipe`（23）；
- **轴向** 在字段 `123`——`1` 水平（Spaces）、`2` 垂直（Mission Control / App Exposé）、`3` Pinch；
- **进度**（控速值）在字段 `124` 累计；
- **相位**（`began`/`changed`/`ended`）在字段 `132`；
- **方向**（上/下、左/右、捏合/张开）＝累计 delta 的**符号**；
- 投递到 **session** 事件 tap。

私有字段布局逐字移植自 **Mac Mouse Fix**（`Helper/Core/Touch/TouchSimulator.m`），
本仓库附了一份副本 [`TouchSimulator.reference.m`](./TouchSimulator.reference.m)。

## 安装

### Homebrew（推荐）

```sh
brew install oomol-lab/tap/dockswipe
```

（`brew install` 会自动 tap 本仓库。）每个版本会为 Apple silicon 与 Intel 分别
发布一个经 Developer ID 签名的二进制，formula 会自动选择对应架构。

### 直接下载

从 [Releases](https://github.com/oomol-lab/dockswipe/releases) 页面获取
`dockswipe-<version>-<arch>.tar.gz`。二进制经过签名但**未公证**，因此用浏览器
下载的文件会被隔离——首次运行前先清除隔离属性：

```sh
tar -xzf dockswipe-*-arm64.tar.gz
xattr -d com.apple.quarantine dockswipe   # 仅浏览器下载时需要
```

（通过 Homebrew 安装的不会被隔离，无需此步。）

## 编译

```sh
make build
# 或直接调用编译器：
clang -O2 -Wall -framework CoreGraphics -framework ApplicationServices -o dockswipe dockswipe.m
```

可选安装：`make install`（默认到 `/usr/local/bin`，可用 `PREFIX=...` 覆盖）。

`dockswipe --version` 显示的版本号在编译期写入：本地构建默认
`0.0.0-development`，可用 `make build VERSION=1.2.3` 覆盖（发布流水线即以此注入
真实版本号）。

## 发布

发布只需一键：在 GitHub 进入 **Actions → Release → Run workflow**。版本号留空
则从最新 tag 自动递增（默认 patch，也可选 `minor`/`major`），或直接填写
`X.Y.Z`。流水线会编译并签名两种架构、发布带 tarball 的 GitHub Release，并更新
[oomol-lab/homebrew-tap](https://github.com/oomol-lab/homebrew-tap) 中的 Homebrew
formula。没有 Beta 渠道——每个版本都是稳定版。

## 权限

在「系统设置 → 隐私与安全性 → 辅助功能」中给**运行它的终端 / 二进制**授权。
无需关闭 SIP、无需特殊 entitlement、无需代码注入。

## 用法

```
dockswipe <预设> [选项]
dockswipe --axis <轴向> --direction <方向> [选项]
```

### 预设

| 预设 | 轴向 | 方向 | 效果 |
| --- | --- | --- | --- |
| `mission-control` | vertical | up | 打开 Mission Control |
| `app-expose` | vertical | down | App Exposé（前台 App 的窗口） |
| `space-left` | horizontal | left | 切到左边的桌面 |
| `space-right` | horizontal | right | 切到右边的桌面 |
| `show-desktop` | pinch | out | 张开手指显示桌面 |
| `launchpad` | pinch | in | 捏合打开 Launchpad |

### 选项

| 选项 | 默认 | 含义 |
| --- | --- | --- |
| `--axis <vertical\|horizontal\|pinch>` | — | 覆盖/指定轴向 |
| `--direction <up\|down\|left\|right\|in\|out>` | — | 覆盖/指定方向 |
| `--offset <浮点>` | `1.5` | 累计滑动总量（约 1.0–3.0 = 整屏） |
| `--steps <整数>` | `25` | 动画帧数（越多越平滑） |
| `--interval <微秒>` | `8000` | 帧间隔微秒（≈ 真实触控板） |
| `--duration <毫秒>` | — | 手势总时长；设了就**覆盖** `--interval` |
| `--invert` | 关 | 翻转方向符号（应对自然滚动设置） |
| `--repeat <整数>` | `1` | 整个手势重复 N 次 |
| `--repeat-delay <毫秒>` | `400` | 每次重复之间的停顿 |
| `--tap <session\|hid>` | `session` | 投递到哪个事件 tap（兼容性备选） |
| `--end-resends <整数>` | `1` | 额外重发 `Ended` 的次数（防手势卡住） |
| `--end-resend-delay <毫秒>` | `200` | 每次重发前的延迟 |
| `-n, --dry-run` | 关 | 只打印事件流，不真正注入 |
| `-v, --verbose` | 关 | 打印每一帧 |
| `-h, --help` | — | 显示帮助 |
| `-V, --version` | — | 打印版本 |

### 速率控制

`速率 = 总位移 / (帧数 × 帧间隔)`。每帧步长越大、帧间隔越短 = 越快；
帧数越多 + 帧间隔越长 = 越慢越平滑。

```sh
dockswipe mission-control --steps 60 --interval 12000      # 慢、丝滑
dockswipe space-right     --offset 2.0 --steps 12 --interval 4000   # 快
dockswipe mission-control --duration 500                   # 总共约 0.5 秒
```

### 示例

```sh
dockswipe mission-control
dockswipe app-expose --duration 300
dockswipe --axis horizontal --direction left --repeat 2 --repeat-delay 600
dockswipe space-right --dry-run -v          # 检查事件流，不真正注入
```

## 限制与注意事项

- **macOS 版本**：字段方案已知可用于 **macOS 10.11 – 26（Tahoe）**。**macOS 27 起**字段路径失效，
  需改为构造 `IOHIDEvent` 并通过 `CGEventSetHIDEvent` 附加（见 `TouchSimulator.reference.m` 里的
  `@available(macOS 27.0, *)` 分支；跟踪：Mac Mouse Fix issue #1876，其中也提到 27 beta 上的
  「手势卡住」bug）。
- **垂直 Mission Control 是源码确认，但无独立最小复现**：最小样例（`joshuarli/iss`、`zackbart/mrmouse`）
  只跑了水平轴；垂直映射来自阅读 Mac Mouse Fix 源码。**请在目标系统上实测。**
- **方向符号**取决于「自然滚动」设置——若方向相反，用 `--invert`。
- **手势卡住**：高负载下 `Ended` 事件可能丢失，使手势卡在动画中途。`--end-resends` 可缓解
  （Mac Mouse Fix 在 0.2s/0.5s 各重发一次 end 事件）。
- **commit 还是 peek**：累计位移量决定 Mission Control 是真正打开还是「探一下又弹回」。
  完全打开的阈值不在源码里——请按机器/系统标定 `--offset`。
- **私有 API**：所有字段索引均未公开，Apple 可能在版本间重新编号。不兼容 App Store。
  作者未实测——依赖前请自行验证。

## 致谢与来源

- **[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)** ——
  `Helper/Core/Touch/TouchSimulator.m`（承重的字段布局、垂直轴、pre-27 与 macOS-27 两条路径）。
  Issue [#1876](https://github.com/noah-nuebling/mac-mouse-fix/issues/1876)。
- **[joshuarli/iss](https://github.com/joshuarli/iss)** —— 单文件 dock-swipe 注入器
  （水平 Spaces）；确认了字段索引与相位枚举。
- **[zackbart/mrmouse](https://github.com/zackbart/mrmouse)** —— 确认该技术在 macOS 26 Tahoe 仍可用。

## 许可证

原始字段布局源自 Mac Mouse Fix（MIT）。本移植请据此处理。
