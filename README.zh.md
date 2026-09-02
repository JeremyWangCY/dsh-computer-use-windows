# dsh-pc-pilot

[English](./README.md) | 中文

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![Node](https://img.shields.io/badge/node-%E2%89%A522.12-green)
![DSH](https://img.shields.io/badge/DeepSeek%20Harness-host%20plugin-blueviolet)

**PC-Pilot（`dsh-pc-pilot`）** 是一个 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）宿主插件，让 AI 模型通过单一 `computer` 工具观察并操作本地 Windows 桌面。

它把三件事整合进一个工具：

1. **看**：索引化的 UIA 无障碍树 + 逐窗口 PNG 截图——模型"读"到的是结构化元素列表（index / role / name / value / automation_id / rect / invokable），而不是靠视觉猜坐标；
2. **动**：默认走**后台合成输入**（UIA 动作模式 → 像素命中测试 → 窗口消息），全程不抢焦点、不动你的真实鼠标键盘；
3. **看得见**：每个动作执行前，屏幕上会出现一个 **codex 风格的虚拟光标**（圆润白色箭头 + 柔和蓝色径向光晕）移动到目标点——点击穿透、绝不取焦点，让人能实时看清 AI 正要做什么。

需要真键鼠的场景（画布点击、不支持的拖拽等）可按任务切换 `dispatch: "foreground"`（真实 SendInput）。

## 特性总览

| 特性 | 说明 |
| --- | --- |
| 单工具全桌面 | `list_apps` / `get_app_state` / `click_element` / `click` / `set_value` / `type` / `key` / `scroll` / `drag` / `open_app` 十个动作覆盖日常桌面操作 |
| 后台优先输入 | 三级回退通道：UIA 动作模式 → 像素命中测试 → `WM_CHAR` / `WM_KEY` / `WM_MOUSEWHEEL` 消息；不把目标窗口带回前台，不占用真实键鼠 |
| 按任务判断 dispatch | `foreground`（真实 SendInput）作为逃生舱口；工具指引要求模型保持 background 默认、切换时明确说明、不静默循环重试 |
| 虚拟光标指示器 | `UpdateLayeredWindow` + `CreateDIBSection` 逐像素透明分层窗口：黑描边圆润白箭头 + 柔和蓝色径向光晕；`WS_EX_TRANSPARENT` 点击穿透、`WS_EX_NOACTIVATE` + `SW_SHOWNOACTIVATE` 永不抢焦点、置顶显示 |
| 3 秒自动隐藏 | 最后一个动作 3 秒后光标自动消失（即 AI 本轮输出结束光标随之关闭），下一个动作再出现 |
| 高 DPI 精确落点 | overlay 启动即调 `SetProcessDPIAware`，以物理像素定位，与 UIA 上报的物理坐标一致；100% / 125% / 150% 缩放下均准确 |
| 逐窗口截图 | 基于 `PrintWindow` 的捕获，随 `get_app_state { screenshot: true }` 返回 PNG 路径 |
| 零依赖零配置 | 唯一外部导入是 DSH 官方运行时自带的 `@deepseek-ai/dsh-tools`；无守护进程、无驱动、无需管理员权限 |

## 环境要求

- **操作系统**：Windows 10 或 Windows 11
- **宿主**：DeepSeek Harness（DSH），`web` profile 中加载 `dsh-pc-pilot` bundle
- **运行时**：Node.js ≥ 22.12（DSH 自带）与 PowerShell 5.1（Windows 系统内置）

## 安装

### 方式一：DSH 插件市场（推荐）

收录后，在 DSH 市场中搜索 **dsh-pc-pilot**（或 PC-Pilot），一键安装并按提示重启宿主。

### 方式二：GitHub Release 预构建包

在 DSH profile 目录（`~/.dsh/profiles/web`）内执行：

```powershell
pnpm add https://github.com/JeremyWangCY/dsh-pc-pilot/releases/download/v0.1.0-beta.1/dsh-pc-pilot-0.1.0-beta.1.tgz
```

确认 profile 的 `package.json` 中 `dsh.profile.bundles` 数组包含 `"dsh-pc-pilot"`（市场安装会自动加入；手动安装需自行添加），然后重启 DSH 宿主。

### 方式三：从源码安装

```powershell
git clone https://github.com/JeremyWangCY/dsh-pc-pilot.git
cd dsh-pc-pilot
pnpm add ./dsh-pc-pilot
```

或者手动 link 调试：把仓库放到 profile 的 `vendor/` 下，在 profile `package.json` 的依赖中写 `"dsh-pc-pilot": "link:./vendor/dsh-pc-pilot"`，`dsh.profile.bundles` 中加入 `"dsh-pc-pilot"`，`pnpm install` 后重启宿主。

### 验证安装

宿主启动日志（或 `%TEMP%\dsh-cua-diag.log` 诊断文件）出现：

```
[computer-use] computer tool registered globally (persistent profile plugin; helper at ...)
```

即表示 `computer` 工具注册成功。

## 使用

### 典型工作流

```jsonc
// 1. 看看有哪些应用
computer { "action": "list_apps" }

// 2. 读取目标应用的结构化状态 + 截图
computer { "action": "get_app_state", "app": "Notepad", "screenshot": true }

// 3. 依据状态执行动作（元素 index 来自上一步）
computer { "action": "click_element", "app": "Notepad", "element": 7 }
computer { "action": "type", "app": "Notepad", "text": "Hello, PC-Pilot!" }

// 4. UI 变化后刷新状态再继续（元素 index 只对产生它的那次 get_app_state 有效）
```

### 动作参考

| 动作 | 用途 | 关键参数 |
| --- | --- | --- |
| `list_apps` | 列出运行中的应用（pid、窗口标题、hwnd、rect） | 无 |
| `get_app_state` | 构建目标窗口的索引化无障碍树，可选截图；应用支持时会附带 `document_text` | `app`、`screenshot` |
| `click_element` | 点击无障碍树中的某个元素（后台 Invoke/命中） | `app`、`element` |
| `click` | 在窗口局部坐标（带 `app`）或屏幕坐标（不带）点击 | `app`?、`x`、`y` |
| `set_value` | 直接设置元素的文本值（走 UIA ValuePattern，比逐字输入快且稳） | `app`、`element`、`value` |
| `type` | 通过 Unicode 输入法逐字输入文本 | `app`?、`text` |
| `key` | 按键（Return、Escape、Tab、F1-F24、a-z、标点等） | `app`?、`key`、`modifiers`（ctrl,shift,alt,win 逗号分隔） |
| `scroll` | 滚轮滚动 | `app`?、`x`、`y`、`amount`（默认 3）、`direction`（down/up） |
| `drag` | 拖拽（部分场景需要 foreground） | `app`?、`from_x`、`from_y`、`to_x`、`to_y` |
| `open_app` | 按名称启动应用 | `name` |

> `app` 可以是 pid 数字、进程名或窗口标题子串；一个进程有多个窗口时用 `window_index`（1 起）消歧。

### dispatch：后台与前台

| 模式 | 行为 | 适用 |
| --- | --- | --- |
| `background`（默认） | UIA 动作模式 → 像素命中测试 → `WM_CHAR`/`WM_KEY`/`WM_MOUSEWHEEL`；不抢焦点、不动真实键鼠 | 绝大多数 UI 自动化 |
| `foreground` | 真实 SendInput：移动真实光标、真实点击、把窗口带向前台 | 画布/游戏类点击、无后台路径的 WinUI/Chromium 表面、真实拖拽 |

工具指引会要求模型：保持 background 默认；仅当用户明确要求真实键鼠、或任务必需的动作确实没有后台路径时才切 foreground，并且**明确告知用户**、一次做完受影响步骤、不静默循环重试。当后台路径不可用时，helper 返回 `background_unavailable: true` 及解释信息。

### overlay：虚拟光标指示器

- **渲染**：48×48 逐像素透明 DIB，`UpdateLayeredWindow` 直绘——柔和蓝色径向光晕（`PathGradientBrush`，中心 alpha 130 渐变到 0，无硬边）叠加圆角白色箭头（`LineJoin.Round`）与黑色描边。
- **行为**：每个动作前移动到目标点；`SW_HIDE` 隐藏 / `SW_SHOWNOACTIVATE` 显示；最后一个动作 **3 秒后自动隐藏**（AI 本轮输出结束即消失），期间点击穿透、不夺焦点、不影响真实键鼠。
- **DPI**：进程启动即 `SetProcessDPIAware`，窗口坐标即物理像素，与 helper 写入状态文件的 UIA 物理坐标一致——125% 缩放下也精确落点。
- **开关**：单次动作传 `overlay: false` 可隐藏。

## 工作原理

```
模型 ── computer 工具 ──> DSH 宿主进程（Node ESM bundle，lib/index.js）
                            │
                            │ 每个动作 spawn 一次 PowerShell 5.1 helper
                            │ （JSON 从 argv 进，JSON 从 stdout 出）
                            ▼
                    lib/computer-use-helper.ps1
                            │
                            ├─> UIA 无障碍树（IUIAutomation COM）
                            ├─> PrintWindow / CopyFromScreen 截图
                            ├─> 后台输入：UIA 模式 → 像素命中 → WM_* 消息
                            ├─> 前台输入：SendInput
                            └─> 写光标状态文件（%TEMP%\dsh-cua\cursor.state）
                                        │
                                        ▼
                    lib/virtual-cursor-overlay.ps1（常驻低频循环）
                            │  SetProcessDPIAware → CreateDIBSection 48×48
                            │  绘制光晕+箭头 → UpdateLayeredWindow 定位显示
```

- **helper**：单文件自包含 PowerShell 脚本，宿主启动时从包内复制到 `%TEMP%\dsh-cua-helper.ps1`，每个动作独立进程执行，无常驻后台。
- **overlay**：`virtual-cursor-overlay.ps1` 常驻循环（100ms 轮询状态文件），内嵌 C#（`Add-Type`）实现分层窗口；`isConcurrencySafe: false` 使桌面动作在宿主侧串行执行。
- **注册**：`defineTool`（`@deepseek-ai/dsh-tools`，DSH 官方运行时包）+ `ctx.tools.register`，带三级加载回退与文件级启动诊断（`%TEMP%\dsh-cua-diag.log`）。

## 安全与隐私

- **能力边界**：该工具可读取窗口标题、无障碍树与截图，并可向用户应用注入输入。内置工具指引明确要求模型**只操作用户 explicitly 要求**的应用与窗口，未经明确指示**绝不**提交表单、发送消息、下单购买、删除数据或更改账号/设置。
- **最小干扰**：后台动作绝不移动真实光标、绝不抢焦点；foreground 动作会——指引要求模型必须先说明再做。
- **无网络、无遥测**：插件不发起任何网络请求；除 `%TEMP%\dsh-cua-*` 状态与诊断文件外不做任何持久化。
- **开源可审计**：全部逻辑就在 `lib/` 两个 PowerShell 文件和一个 JS 文件里，欢迎审阅。

## 故障排查

| 现象 | 原因与处理 |
| --- | --- |
| `computer` 工具不存在 | 确认 profile `dsh.profile.bundles` 含 `dsh-pc-pilot` 且宿主已重启；查看 `%TEMP%\dsh-cua-diag.log` 的启动诊断（模块加载 / apply / 注册三步各有记录） |
| 光标指示器不出现 | 同上查诊断日志；确认没有第二个旧版 overlay 进程残留（可在任务管理器搜 powershell） |
| 光标可见但位置偏移 | 安装版本必须调用 `SetProcessDPIAware`（≥ 0.1.0 均有）；DPI 感知不匹配会使位置按缩放系数偏移（如 125% 下偏 25%） |
| 桌面图标消失 / 出现灰色方块 | Windows shell（WorkerW）故障，通常由桌面整理或壁纸类工具触发，**与本插件无关**（本插件从不触碰 Progman/WorkerW）；重启 `explorer.exe` 即可恢复 |
| 返回 `background_unavailable` | 目标没有后台路径（画布、部分 WinUI/Chromium 表面、真实拖拽）。按任务判断是否切 `foreground` |
| 截图黑屏/空白 | DirectComposition/UWP 窗口或最小化窗口；以 `screenshot.error` 为准，改用无障碍树操作 |

## 开发

```text
lib/index.js                    宿主端：工具注册（defineTool + ctx.tools.register）、helper 调度
lib/computer-use-helper.ps1     单文件 helper：UIA / 截图 / 输入 / 光标通知
lib/virtual-cursor-overlay.ps1  常驻 overlay：内嵌 C# 分层窗口渲染
scripts/smoke-test.ps1          冒烟测试：对真实窗口执行 list_apps / get_app_state / 后台点击
docs/plugin-entry.yml           awesome-dsh-plugin 目录收录条目
```

```powershell
git clone https://github.com/JeremyWangCY/dsh-pc-pilot.git
cd dsh-pc-pilot
pwsh -File scripts/smoke-test.ps1
```

本地调试：把仓库复制（或 link）到 profile 的 `vendor/` 下，按上文"从源码安装"配置后重启宿主。

## 许可证

[MIT](LICENSE)