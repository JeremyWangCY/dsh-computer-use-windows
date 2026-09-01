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

## 后台合成光标模式


`computer` 工具默认 **`dispatch: background`**：输入不抢真实鼠标/键盘，也不把目标窗口
带回前台（codex-style，参照 cua-driver 的 Windows 后台路线）。

- **后台输入**：优先用 UIA 动作模式（Invoke / Toggle / Selection / ExpandCollapse /
  RangeValue / Transform），再到像素点命中测试，最后用 `WM_CHAR` / `WM_KEY` /
  `WM_MOUSEWHEEL` 消息投递给目标控件句柄。
- **诚实降级**：某点/某控件在后台没有可行路径时（画布点击、无原生 HWND 的 WinUI /
  Chromium 目标、不支持的拖拽），helper 返回 `background_unavailable: true` 并说明原因，
  可直接对单个动作改用 `"dispatch": "foreground"`（真实 SendInput，带回前台并回报
  `focus_ok`）。
- **不干扰你正常使用**：不抢真实键鼠、不把目标窗口带回前台。默认会在 AI 即将点击/输入的位置显示一个**小号点击穿透的 codex 风格光标**（圆润白色箭头 + 柔和蓝色径向光晕；默认开，你在意就在动作上传 `overlay: false` 隐藏）。它绝不取焦点、点击可穿透，跟随每个动作点移动，并在**最后一个动作 3 秒后自动隐藏**——也就是 AI 本轮输出结束时光标随之消失，下一个动作再出现。已适配高 DPI（坐标为物理像素，125% 缩放下也精确落点）。

| 参数 | 默认 | 说明 |
|------|------|------|
| `dispatch` | `background` | `background` 后台合成光标输入；`foreground` 真实 SendInput——按任务判断：仅在用户明确要求真实键鼠、或任务必需的动作没有后台路径时使用，并明确告知 |
| `overlay` | `true` | 真实键鼠不动的前提下，在动作点显示圆润箭头+柔和蓝光（`overlay: false` 隐藏）；最后一个动作 3 秒后自动消失 |

## 架构

- 宿主进程内 ESM 插件（`lib/index.js`），直接 spawn **Windows PowerShell 5.1**
  （`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`）。
- `lib/computer-use-helper.ps1` 一次性拷到 %TEMP% 后以 JSON 载荷调用（argv 传参、stdout 回 JSON）。
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
