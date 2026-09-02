# dsh-pc-pilot

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey)
![Node](https://img.shields.io/badge/node-%E2%89%A522.12-green)

一个 **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 宿主插件**，为模型提供单一 `computer` 工具以观察和操作本地 Windows 桌面：索引化 UIA 无障碍树、逐窗口截图、不抢焦点的后台合成输入，以及在任务确有需要时的真实 SendInput 键鼠控制。

执行动作时，模型会把一个 **codex 风格的屏幕光标**（圆润白色箭头 + 柔和蓝色径向光晕）移动到每个目标点，让人能看清 AI 正要点哪里、输入什么。该光标点击穿透、绝不取焦点，并在最后一个动作 3 秒后自动隐藏。

## 特性

- **一个工具，整个桌面** —— `list_apps`、`get_app_state`、`click_element`、`click`、`set_value`、`type`、`key`、`scroll`、`drag`、`open_app`。
- **后台优先的输入** —— 动作经 UIA 动作模式（Invoke / Toggle / Selection / ExpandCollapse / RangeValue / Transform）→ 像素命中测试 → `WM_CHAR` / `WM_KEY` / `WM_MOUSEWHEEL` 消息执行。不把目标窗口带回前台，不占用用户真实键鼠。
- **按任务判断 dispatch** —— `dispatch: "foreground"`（真实 SendInput）留给真正需要的场景（画布点击、不支持的拖拽、无后台路径的应用）；工具指引保持 background 为默认，并要求模型切换时明确说明。
- **虚拟光标指示器** —— 逐像素透明分层窗口（`UpdateLayeredWindow` + `CreateDIBSection`）：黑描边圆润白箭头叠加柔和蓝色径向光晕。点击穿透（`WS_EX_TRANSPARENT`）、不激活（`WS_EX_NOACTIVATE` + `SW_SHOWNOACTIVATE`）、置顶。最后一个动作 3 秒后自动隐藏，下一个动作再出现。
- **高 DPI 精确落点** —— overlay 启动即调 `SetProcessDPIAware`，以物理像素定位，与 helper 上报的 UIA 物理坐标一致。100% / 125% / 150% 缩放下均准确。
- **窗口截图** —— 基于 `PrintWindow` 的逐窗口捕获，随 `get_app_state { screenshot: true }` 返回 PNG。
- **零配置** —— 无守护进程、无驱动、无需管理员权限。全部通过包内自带的 Windows PowerShell 5.1 helper 运行。

## 环境要求

- Windows 10 或 11
- DeepSeek Harness（DSH），`web` profile 中加载 `dsh-pc-pilot` bundle
- PowerShell 5.1（系统内置）与 Node.js ≥ 22.12（DSH 自带）

## 安装

### 从 DSH 插件市场

收录后，在市场中搜索 *dsh-pc-pilot* 一键安装。

### 从 GitHub Release

```powershell
pnpm add https://github.com/JeremyWangCY/PC-Pilot/releases/download/v0.1.0-beta.1/dsh-pc-pilot-0.1.0-beta.1.tgz
```

在 DSH profile 目录（`~/.dsh/profiles/web`）内执行，然后重启宿主。

### 从源码

```powershell
git clone https://github.com/JeremyWangCY/PC-Pilot.git
cd dsh-pc-pilot
pnpm add ./dsh-pc-pilot
```

或手动 link：在 profile 的 `package.json` 依赖中加入 `"dsh-pc-pilot": "link:./vendor/dsh-pc-pilot"`，把 bundle 加进 `dsh.profile.bundles`，`pnpm install` 后重启宿主。

## 使用

插件注册一个全局工具 `computer`。典型流程：

1. `computer { action: "list_apps" }` —— 运行中的应用（pid、窗口标题、hwnd、rect）。
2. `computer { action: "get_app_state", app: "Notepad", screenshot: true }` —— 索引化无障碍树（元素 index / role / name / value / automation_id / rect / invokable）+ 窗口截图。
3. 依据状态执行 —— `click_element { app, element }`、`set_value { app, element, value }`、`type { app, text }`、`key { app, key, modifiers }`、`scroll { app, x, y, amount, direction }`、`drag { app, from_x, from_y, to_x, to_y }`。
4. 每次 UI 变化后刷新状态；元素 index 仅对产生它的那次 `get_app_state` 有效。

### 关键参数

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `dispatch` | `background` | UIA 模式 + 窗口消息，不抢焦点。`foreground` 使用真实 SendInput——仅当用户明确要求真实键鼠、或任务必需的动作没有后台路径时按任务选用。 |
| `overlay` | `true` | 在动作点显示点击穿透光标；最后一个动作 3 秒后自动隐藏。 |
| `screenshot` | `true` | `get_app_state` 时捕获逐窗口 PNG。 |
| `app` | — | pid 数字、进程名或窗口标题子串；多窗口时用 `window_index` 消歧。 |
| `x` / `y` | — | 窗口局部像素（带 `app`）或屏幕坐标（不带）。 |

## 工作原理

```
model ── computer 工具 ──> 宿主（Node ESM bundle）
                              │  每个动作 spawn 一次 PowerShell 5.1 helper（JSON 进 / JSON 出）
                              ├─> UIA 无障碍树（IUIAutomation）
                              ├─> PrintWindow / CopyFromScreen 截图
                              ├─> 后台输入：UIA 模式 → 像素命中 → WM_* 消息
                              ├─> 前台输入：SendInput
                              └─> overlay：UpdateLayeredWindow 逐像素透明分层窗口
```

helper 是单个自包含的 `computer-use-helper.ps1`，宿主启动时复制到 `%TEMP%`；overlay 是 `virtual-cursor-overlay.ps1`，常驻低频循环读取状态文件并用 `UpdateLayeredWindow` 绘制 48×48 DIB。注册走 harness 工具 API（`defineTool` + `ctx.tools.register`），`isConcurrencySafe: false` 保证桌面动作串行执行。

## 安全与隐私

- 该工具能读取窗口标题、无障碍树与截图，并能向用户应用注入输入。内置工具指引要求模型**只操作用户明确要求**的目标，且未经明确指示绝不提交表单、发送消息、下单购买、删除数据或更改账号/设置。
- 后台动作绝不移动用户光标、绝不抢焦点；前台动作会——指引要求模型必须说明。
- 无网络访问、无遥测；除 `%TEMP%\dsh-cua-*` 状态文件外不做任何持久化。

## 故障排查

- **光标指示器不出现** —— 查看 `%TEMP%\dsh-cua-diag.log`（启动诊断），确认安装后重启过宿主。
- **指示器可见但位置偏移** —— 确认安装版本调用了 `SetProcessDPIAware`（≥ 0.1.0 均有）；DPI 感知不匹配会使 overlay 按缩放系数偏移。
- **桌面图标消失 / 出现灰色方块** —— 这是 Windows shell（WorkerW）故障，通常由桌面整理或壁纸类工具触发，与本插件无关；重启 `explorer.exe` 即可恢复。
- **`background_unavailable`** —— 目标没有后台路径（画布、部分 WinUI/Chromium 表面）。按任务判断是否切换 `foreground`。

## 开发

```powershell
git clone https://github.com/JeremyWangCY/PC-Pilot.git
cd dsh-pc-pilot
pwsh -File scripts/smoke-test.ps1
```

冒烟测试对真实窗口执行 helper 动作（`list_apps`、`get_app_state`、后台点击）。要从本地 checkout 运行插件，按上文方式 link 进 DSH profile。

## 许可证

[MIT](LICENSE)
