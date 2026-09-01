# dsh-computer-use (Windows)

适用于 **Windows** 的 DeepSeek Harness Computer Use 宿主插件：
通过 **UIA 无障碍树 + PrintWindow 截图 + SendInput** 真实键鼠操作本地桌面
（镜像 zcode/codex computer use 的工具形态）。

## 功能

注册全局模型工具 `computer`，动作一览：

| 动作 | 说明 |
|------|------|
| `list_apps` | 列出运行中的应用（pid / 名称 / 窗口标题 / 句柄 / 位置）|
| `get_app_state` | 聚焦窗口，构建带索引的 UIA 无障碍树，可选保存窗口 PNG 截图 |
| `click_element` | 按 UIA 元素索引点击 |
| `click` | 按窗口内坐标点击 |
| `set_value` | 设置元素文本值 |
| `type` | Unicode 文本输入 |
| `key` | 按键（Enter / Tab / 方向键 / F1-F24 等，可带 ctrl/shift/alt/win）|
| `scroll` | 窗口内滚轮 |
| `drag` | 窗口内拖拽 |
| `open_app` | 启动应用 |

安全约束：元素索引只在产生它的那次 `get_app_state` 内有效；只操作用户明确指定的应用与窗口。

## 后台合成光标模式 + 虚拟光标悬浮层

`computer` 工具默认 **`dispatch: background`**：输入不抢真实鼠标/键盘，也不把目标窗口
带回前台（codex-style，参照 cua-driver 的 Windows 后台路线）。

- **后台输入**：优先用 UIA 动作模式（Invoke / Toggle / Selection / ExpandCollapse /
  RangeValue / Transform），再到像素点命中测试，最后用 `WM_CHAR` / `WM_KEY` /
  `WM_MOUSEWHEEL` 消息投递给目标控件句柄。
- **诚实降级**：某点/某控件在后台没有可行路径时（画布点击、无原生 HWND 的 WinUI /
  Chromium 目标、不支持的拖拽），helper 返回 `background_unavailable: true` 并说明原因，
  可直接对单个动作改用 `"dispatch": "foreground"`（真实 SendInput，带回前台并回报
  `focus_ok`）。
- **虚拟光标悬浮层**（`overlay: true`）：每次输入动作前，在目标点旁浮现一个 codex 式
  透明、点击穿透、置顶的小药丸窗口，显示 AI 当前虚拟光标位置和动作标签，约 1s 后淡出；
  右上角 `x` 可隐藏。若要完全关闭，传 `"overlay": false`。

| 参数 | 默认 | 说明 |
|------|------|------|
| `dispatch` | `background` | `background` 后台合成光标输入；`foreground` 真实 SendInput |
| `overlay` | `true` | 显示/隐藏虚拟光标悬浮层 |

## 架构

- 宿主进程内 ESM 插件（`lib/index.js`），直接 spawn **Windows PowerShell 5.1**
  （`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`）。
- `lib/computer-use-helper.ps1` 一次性拷到 %TEMP% 后以 JSON 载荷调用（argv 传参、stdout 回 JSON）。
- `lib/virtual-cursor-overlay.ps1` 由 helper 按需自启：TransparencyKey 分层、置顶、点击穿透
  （WM_NCHITTEST 命中测试放行除 `x` 键区外的区域），每次动作后显示约 1s。
- 无额外原生二进制依赖，Windows 自带 PowerShell 即可工作。

## 安装

```bash
# 方式一：市场安装（需要已发布到 GitHub/npm 后）
dsh plugin --profile web add dsh-computer-use-windows

# 方式二：本地链接（本仓库）
cd C:\Users\Laptop\dsh-computer-use-windows
dsh plugin --profile web add "link:./"
```

## 自测

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
```

## 许可证

MIT
