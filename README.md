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

安全约束：元素索引只在产生它的那次 `get_app_state` 内有效；输入动作会先把目标窗口
带到前台并回报是否聚焦成功；只操作用户明确指定的应用与窗口。

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
