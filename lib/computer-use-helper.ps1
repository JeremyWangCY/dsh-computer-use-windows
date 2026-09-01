# dsh computer-use helper (Windows PowerShell 5.1)
# Background synthetic-cursor semantics per cua-driver's Windows recipe:
#   dispatch=background (default): UIA patterns first, then pixel hit-test, then
#   WM_CHAR/WM_KEY/WM_MOUSEWHEEL messages. Never steals foreground. Actions that
#   cannot run in background return background_unavailable (caller may retry with
#   dispatch=foreground = real SendInput).
# Actions: list_apps, get_app_state, click, click_element, set_value, type, key,
#   scroll, drag, open_app. Usage: powershell -NoProfile -ExecutionPolicy Bypass
#   -File <this> -Action <action> -PayloadJson "<json>"; writes ONE JSON doc to stdout.
param(
  [string]$Action,
  [string]$PayloadJson = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:MAX_ELEMENTS = 500

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName WindowsBase

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class DshWin32
{
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X, Y; }

  [StructLayout(LayoutKind.Sequential)]
  public struct WinInfo
  {
    public IntPtr Hwnd;
    public uint Pid;
    public string Title;
    public bool Visible;
    public bool Foreground;
    public RECT Rect;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct INPUTUNION
  {
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public INPUTUNION u; }

  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);

  public static List<WinInfo> EnumWindowsList()
  {
    List<WinInfo> list = new List<WinInfo>();
    IntPtr fg = GetForegroundWindow();
    EnumWindows(delegate(IntPtr h, IntPtr l)
    {
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      if (r.Right - r.Left <= 0 || r.Bottom - r.Top <= 0) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      StringBuilder sb = new StringBuilder(512);
      GetWindowText(h, sb, 512);
      WinInfo wi = new WinInfo();
      wi.Hwnd = h; wi.Pid = pid; wi.Title = sb.ToString(); wi.Visible = true;
      wi.Foreground = (h == fg); wi.Rect = r;
      list.Add(wi);
      return true;
    }, IntPtr.Zero);
    return list;
  }

  public static RECT GetRect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }

  public static void ForceForeground(IntPtr h)
  {
    ShowWindow(h, 9);
    INPUT[] alt = new INPUT[] { MkKey(0x12, 0), MkKey(0x12, 2) };
    SendInput(2, alt, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(40);
    INPUT[] esc = new INPUT[] { MkKey(0x1B, 0), MkKey(0x1B, 2) };
    SendInput(2, esc, Marshal.SizeOf(typeof(INPUT)));
    System.Threading.Thread.Sleep(40);
    IntPtr f = GetForegroundWindow();
    uint fgTid; GetWindowThreadProcessId(f, out fgTid);
    uint hTid; GetWindowThreadProcessId(h, out hTid);
    if (fgTid != hTid) AttachThreadInput(fgTid, hTid, true);
    BringWindowToTop(h);
    SetForegroundWindow(h);
    SetFocus(h);
    if (fgTid != hTid) AttachThreadInput(fgTid, hTid, false);
    System.Threading.Thread.Sleep(150);
  }

  public static long ForegroundHwnd()
  {
    return GetForegroundWindow().ToInt64();
  }

  private static INPUT MkMouse(uint flags, uint data)
  {
    INPUT i = new INPUT(); i.type = 0; i.u.mi.dx = 0; i.u.mi.dy = 0;
    i.u.mi.mouseData = data; i.u.mi.dwFlags = flags; i.u.mi.time = 0; i.u.mi.dwExtraInfo = IntPtr.Zero;
    return i;
  }

  private static INPUT MkKey(ushort vk, uint flags)
  {
    INPUT i = new INPUT(); i.type = 1; i.u.ki.wVk = vk; i.u.ki.wScan = 0;
    i.u.ki.dwFlags = flags; i.u.ki.time = 0; i.u.ki.dwExtraInfo = IntPtr.Zero;
    return i;
  }

  private static INPUT MkUni(char c, uint flags)
  {
    INPUT i = new INPUT(); i.type = 1; i.u.ki.wVk = 0; i.u.ki.wScan = (ushort)c;
    i.u.ki.dwFlags = flags; i.u.ki.time = 0; i.u.ki.dwExtraInfo = IntPtr.Zero;
    return i;
  }

  public static void TypeText(string text)
  {
    if (string.IsNullOrEmpty(text)) return;
    List<INPUT> ev = new List<INPUT>();
    foreach (char c in text)
    {
      ev.Add(MkUni(c, 4));
      ev.Add(MkUni(c, 6));
    }
    SendInput((uint)ev.Count, ev.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }

  public static ushort MapKey(string key)
  {
    if (string.IsNullOrEmpty(key)) return 0;
    string k = key.Trim().ToLowerInvariant();
    switch (k)
    {
      case "return": case "enter": return 0x0D;
      case "escape": case "esc": return 0x1B;
      case "tab": return 0x09;
      case "backspace": case "bspace": return 0x08;
      case "space": case "spacebar": return 0x20;
      case "delete": case "del": return 0x2E;
      case "insert": case "ins": return 0x2D;
      case "home": return 0x24;
      case "end": return 0x23;
      case "pageup": case "pgup": return 0x21;
      case "pagedown": case "pgdn": return 0x22;
      case "up": case "arrowup": return 0x26;
      case "down": case "arrowdown": return 0x28;
      case "left": case "arrowleft": return 0x25;
      case "right": case "arrowright": return 0x27;
      case "capslock": case "caps": return 0x14;
      case "printscreen": case "prtsc": return 0x2C;
      case "scrolllock": return 0x91;
      case "pause": case "break": return 0x13;
    }
    if (k.Length == 1)
    {
      char c = k[0];
      if (c >= 'a' && c <= 'z') return (ushort)(0x41 + (c - 'a'));
      if (c >= '0' && c <= '9') return (ushort)(0x30 + (c - '0'));
      if (c == '-') return 0xBD; if (c == '=') return 0xBB;
      if (c == '[') return 0xDB; if (c == ']') return 0xDD;
      if (c == '\\') return 0xDC; if (c == ';') return 0xBA;
      if (c == '\'') return 0xDE; if (c == ',') return 0xBC;
      if (c == '.') return 0xBE; if (c == '/') return 0xBF;
      if (c == '`') return 0xC0;
    }
    if (k.StartsWith("f") && k.Length > 1)
    {
      int n; if (int.TryParse(k.Substring(1), out n) && n >= 1 && n <= 24) return (ushort)(0x6F + n);
    }
    return 0;
  }

  public static void KeyChord(string key, string modifiers)
  {
    ushort vk = MapKey(key);
    if (vk == 0) throw new Exception("unknown key: " + key);
    List<ushort> mods = new List<ushort>();
    if (!string.IsNullOrEmpty(modifiers))
    {
      foreach (string part in modifiers.Split(new char[] { ',', '+' }, StringSplitOptions.RemoveEmptyEntries))
      {
        string m = part.Trim().ToLowerInvariant();
        if (m == "ctrl" || m == "control") mods.Add(0x11);
        else if (m == "shift") mods.Add(0x10);
        else if (m == "alt") mods.Add(0x12);
        else if (m == "win" || m == "meta" || m == "super") mods.Add(0x5B);
      }
    }
    List<INPUT> ev = new List<INPUT>();
    foreach (ushort m in mods) ev.Add(MkKey(m, 0));
    ev.Add(MkKey(vk, 0));
    ev.Add(MkKey(vk, 2));
    for (int i = mods.Count - 1; i >= 0; i--) ev.Add(MkKey(mods[i], 2));
    SendInput((uint)ev.Count, ev.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }

  public static void MouseMove(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(40); }

  public static void MouseClick(int x, int y)
  {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(50);
    INPUT[] d = new INPUT[] { MkMouse(0x0002, 0) };
    INPUT[] u = new INPUT[] { MkMouse(0x0004, 0) };
    SendInput(1, d, Marshal.SizeOf(typeof(INPUT))); System.Threading.Thread.Sleep(30);
    SendInput(1, u, Marshal.SizeOf(typeof(INPUT))); System.Threading.Thread.Sleep(30);
  }

  public static void Scroll(int x, int y, int amount, bool down)
  {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(50);
    uint data = (uint)((down ? -1 : 1) * amount * 120);
    INPUT[] ev = new INPUT[] { MkMouse(0x0800, data) };
    SendInput(1, ev, Marshal.SizeOf(typeof(INPUT)));
  }

  public static void Drag(int fx, int fy, int tx, int ty)
  {
    SetCursorPos(fx, fy); System.Threading.Thread.Sleep(60);
    INPUT[] d = new INPUT[] { MkMouse(0x0002, 0) };
    SendInput(1, d, Marshal.SizeOf(typeof(INPUT))); System.Threading.Thread.Sleep(60);
    int steps = Math.Max(6, (Math.Abs(tx - fx) + Math.Abs(ty - fy)) / 12);
    for (int i = 1; i <= steps; i++)
    {
      int cx = fx + (tx - fx) * i / steps;
      int cy = fy + (ty - fy) * i / steps;
      SetCursorPos(cx, cy);
      System.Threading.Thread.Sleep(8);
    }
    System.Threading.Thread.Sleep(60);
    INPUT[] u = new INPUT[] { MkMouse(0x0004, 0) };
    SendInput(1, u, Marshal.SizeOf(typeof(INPUT))); System.Threading.Thread.Sleep(30);
  }
}
'@

# ---------------------------------------------------------------- payload / window helpers

function Get-PayloadValue {
  param([string]$Name)
  if ($null -ne $script:payload -and $script:payload.PSObject.Properties[$Name]) {
    return $script:payload.$Name
  }
  return $null
}

function Get-Dispatch {
  $d = Get-PayloadValue 'dispatch'
  if (-not $d) { $d = 'background' }
  return ([string]$d).ToLowerInvariant()
}

function Get-OverlayEnabled {
  $o = Get-PayloadValue 'overlay'
  if ($null -eq $o) { return $true }
  return [bool]$o
}

function Resolve-TargetWindow {
  param([string]$App, [int]$Index)
  $wins = @([DshWin32]::EnumWindowsList())

  function Filter-Candidates([object[]]$list) {
    return @($list | Where-Object {
      $_.Rect.Left -ge -10000 -and $_.Rect.Top -ge -10000 -and
      ($_.Rect.Right - $_.Rect.Left) -ge 50 -and
      ($_.Rect.Bottom - $_.Rect.Top) -ge 32
    })
  }

  if ($App -match '^\d+$') {
    $pidMatch = [uint32]$App
    $cand = Filter-Candidates @($wins | Where-Object { $_.Pid -eq $pidMatch })
  } else {
    $cand = Filter-Candidates @($wins | Where-Object { $_.Title -like "*$App*" })
    if ($cand.Count -eq 0) {
      $names = @{}
      foreach ($w in $wins) {
        if (-not $names.ContainsKey($w.Pid)) {
          $p = Get-Process -Id $w.Pid -ErrorAction SilentlyContinue
          $names[$w.Pid] = if ($p) { $p.ProcessName } else { '' }
        }
      }
      $cand = Filter-Candidates @($wins | Where-Object { $names[$_.Pid] -ieq $App })
    }
  }
  if ($cand.Count -eq 0) { throw "app_not_found: $App" }
  if ($Index -gt 0) {
    $idx = [Math]::Min($Index, $cand.Count) - 1
  } else {
    $best = 0
    $bestArea = -1
    for ($i = 0; $i -lt $cand.Count; $i++) {
      $area = ($cand[$i].Rect.Right - $cand[$i].Rect.Left) * ($cand[$i].Rect.Bottom - $cand[$i].Rect.Top)
      if ($area -gt $bestArea) { $bestArea = $area; $best = $i }
    }
    $idx = $best
  }
  return $cand[$idx]
}

function Get-WindowInfo {
  param($Win)
  return @{
    hwnd = $Win.Hwnd.ToInt64()
    pid = $Win.Pid
    title = $Win.Title
    foreground = $Win.Foreground
    rect = @{ x = $Win.Rect.Left; y = $Win.Rect.Top; width = ($Win.Rect.Right - $Win.Rect.Left); height = ($Win.Rect.Bottom - $Win.Rect.Top) }
  }
}

function Get-AccessibilityTree {
  param([IntPtr]$Hwnd, [int]$MaxElements = $script:MAX_ELEMENTS)
  $aeRoot = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $children = $aeRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $out = New-Object System.Collections.Generic.List[object]
  $count = 0
  foreach ($el in $children) {
    if ($count -ge $MaxElements) { break }
    $count++
    $cur = $el.Current
    $rect = $cur.BoundingRectangle
    $name = $cur.Name
    $autoId = $cur.AutomationId
    $value = ''
    $vp = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
      try { $value = $vp.Current.Value } catch { }
    }
    if (($name -eq '') -and ($autoId -eq '') -and ($value -eq '') -and ($rect.Width -le 0 -or $rect.Height -le 0)) { continue }
    $invoke = $false
    $ip = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) { $invoke = $true }
    $item = [ordered]@{
      index = $count
      role = $cur.ControlType.ProgrammaticName
      name = if ($name) { $name } else { '' }
      value = if ($value) { $value } else { '' }
      automation_id = if ($autoId) { $autoId } else { '' }
      enabled = $cur.IsEnabled
      offscreen = $cur.IsOffscreen
      invokable = $invoke
      rect = @{ x = [int]$rect.X; y = [int]$rect.Y; width = [int]$rect.Width; height = [int]$rect.Height }
    }
    $out.Add($item)
  }
  return $out
}

function Find-ElementByIndex {
  param([IntPtr]$Hwnd, [int]$Index)
  $aeRoot = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $children = $aeRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $n = 0
  foreach ($el in $children) {
    $n++
    if ($n -eq $Index) { return $el }
  }
  throw "element_not_found: index $Index"
}

function Get-DocumentText {
  param([IntPtr]$Hwnd, [int]$MaxLen = 3000)
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    $tp = $null
    if ($root.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
      return $tp.DocumentRange.GetText($MaxLen)
    }
    $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
      $t2 = $null
      if ($el.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$t2)) {
        return $t2.DocumentRange.GetText($MaxLen)
      }
      $v2 = $null
      if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$v2)) {
        $v = $v2.Current.Value
        if ($v) { return $v }
      }
    }
  } catch { }
  return ''
}

# ---------------------------------------------------------------- overlay + background dispatch

function Ensure-OverlayProcess {
  # ponytail: pid-marker check; races only duplicate a harmless overlay instance
  $dir = Join-Path $env:TEMP 'dsh-cua'
  $pidFile = Join-Path $dir 'overlay.pid'
  if (Test-Path $pidFile) {
    $pidNow = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
    $p = Get-Process -Id ([int]$pidNow) -ErrorAction SilentlyContinue
    if ($p) { return }
  }
  $ov = Join-Path $PSScriptRoot 'virtual-cursor-overlay.ps1'
  if (-not (Test-Path $ov)) { return }
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$ov`"") -WindowStyle Hidden | Out-Null
}

function Write-CursorState {
  param([int]$X, [int]$Y, [string]$Label, [bool]$Show)
  if (-not $Show) { $Label = 'hidden' }
  $dir = Join-Path $env:TEMP 'dsh-cua'
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
  $state = @{ x = $X; y = $Y; label = $Label; ts = $ts; show = $Show } | ConvertTo-Json -Compress
  Set-Content -Path (Join-Path $dir 'cursor.state') -Value $state -Encoding ascii
}

function Notify-Cursor {
  param([int]$X, [int]$Y, [string]$Label)
  $on = Get-OverlayEnabled
  if ($on) { Ensure-OverlayProcess }
  Write-CursorState -X $X -Y $Y -Label $Label -Show $on
}

function Find-TextInputHwnd {
  param([IntPtr]$Hwnd)
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($el in $all) {
    if ($el.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit) {
      $h = $el.Current.NativeWindowHandle
      if ($h -ne 0) { return [IntPtr]$h }
    }
  }
  foreach ($el in $all) {
    $h = $el.Current.NativeWindowHandle
    if ($h -eq 0) { continue }
    $vp = $null; $tp = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { return [IntPtr]$h }
    if ($el.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) { return [IntPtr]$h }
  }
  return [IntPtr]::Zero
}

function Find-ValuePatternEl {
  param([IntPtr]$Hwnd)
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  foreach ($el in $all) {
    $vp = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { return $el }
  }
  return $null
}

function Send-BackgroundText {
  param([IntPtr]$Hwnd, [string]$Text)
  foreach ($ch in $Text.ToCharArray()) {
    if ($ch -eq [char]10) {
      $null = [DshWin32]::SendMessage($Hwnd, 0x0100, [IntPtr]13, [IntPtr]::Zero)
      $null = [DshWin32]::SendMessage($Hwnd, 0x0102, [IntPtr]13, [IntPtr]::Zero)
      $null = [DshWin32]::SendMessage($Hwnd, 0x0101, [IntPtr]13, [IntPtr]::Zero)
      continue
    }
    if ($ch -eq [char]13) { continue }
    $null = [DshWin32]::SendMessage($Hwnd, 0x0102, [IntPtr][int]$ch, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 4
  }
}

function Send-BackgroundKey {
  param([IntPtr]$Hwnd, [string]$Key, [string]$Modifiers)
  $vk = [DshWin32]::MapKey($Key)
  if ($vk -eq 0) { throw "unknown key: $Key" }
  $modVks = @()
  if ($Modifiers) {
    foreach ($part in ($Modifiers -split '[,+]')) {
      $m = $part.Trim().ToLowerInvariant()
      if ($m -in @('ctrl','control')) { $modVks += 0x11 }
      elseif ($m -in @('shift')) { $modVks += 0x10 }
      elseif ($m -in @('alt')) { $modVks += 0x12 }
      elseif ($m -in @('win','meta','super')) { $modVks += 0x5B }
    }
  }
  foreach ($mvk in $modVks) { $null = [DshWin32]::SendMessage($Hwnd, 0x0100, [IntPtr]$mvk, [IntPtr]::Zero) }
  $null = [DshWin32]::SendMessage($Hwnd, 0x0100, [IntPtr]$vk, [IntPtr]::Zero)
  $null = [DshWin32]::SendMessage($Hwnd, 0x0101, [IntPtr]$vk, [IntPtr]::Zero)
  for ($i = $modVks.Count - 1; $i -ge 0; $i--) { $null = [DshWin32]::SendMessage($Hwnd, 0x0101, [IntPtr]$modVks[$i], [IntPtr]::Zero) }
}

function Invoke-FromPoint {
  param([double]$X, [double]$Y)
  $pt = New-Object System.Windows.Point($X, $Y)
  $el = [System.Windows.Automation.AutomationElement]::FromPoint($pt)
  for ($i = 0; $i -lt 12 -and $null -ne $el; $i++) {
    $ip = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) {
      $ip.Invoke(); return @{ ok = $true; method = 'invoke'; name = $el.Current.Name; rect = $el.Current.BoundingRectangle }
    }
    $tp = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$tp)) {
      $tp.Toggle(); return @{ ok = $true; method = 'toggle'; name = $el.Current.Name; rect = $el.Current.BoundingRectangle }
    }
    $sp = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sp)) {
      $sp.Select(); return @{ ok = $true; method = 'selection'; name = $el.Current.Name; rect = $el.Current.BoundingRectangle }
    }
    $el = $el.GetParent()
  }
  return @{ ok = $false }
}

function Get-OverlayPoint-WindowCenter {
  param($Win)
  $cx = [int](($Win.Rect.Left + $Win.Rect.Right) / 2)
  $cy = [int](($Win.Rect.Top + $Win.Rect.Bottom) / 2)
  return @($cx, $cy)
}

function Do-AppState {
  param([string]$App, [int]$WindowIndex, [bool]$WithScreenshot, [string]$Dispatch)
  $win = Resolve-TargetWindow -App $App -Index $WindowIndex
  if ($Dispatch -eq 'foreground') {
    [DshWin32]::ForceForeground($win.Hwnd)
    Start-Sleep -Milliseconds 250
    $fresh = @([DshWin32]::EnumWindowsList() | Where-Object { $_.Hwnd -eq $win.Hwnd })
    if ($fresh.Count -gt 0) { $win = $fresh[0] }
  }
  $shot = $null
  if ($WithScreenshot) {
    $dir = Join-Path $env:TEMP 'dsh-cua'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir ("shot-{0}.png" -f ([guid]::NewGuid().ToString('N')))
    $w = $win.Rect.Right - $win.Rect.Left
    $h = $win.Rect.Bottom - $win.Rect.Top
    $bmp = New-Object System.Drawing.Bitmap([Math]::Max(1, $w), [Math]::Max(1, $h))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [DshWin32]::PrintWindow($win.Hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc)
    $g.Dispose()
    if ($ok) { $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) }
    $black = $false
    if ($ok -and $w -gt 4 -and $h -gt 4) {
      $px = $bmp.GetPixel([int]($w / 2), [int]($h / 2))
      if ($px.R -eq 0 -and $px.G -eq 0 -and $px.B -eq 0) { $black = $true }
    }
    $bmp.Dispose()
    if ($ok) {
      $shot = @{
        path = $path
        width = $w
        height = $h
        scale = 1
        window_rect = @{ x = $win.Rect.Left; y = $win.Rect.Top }
      }
      if ($black) { $shot.error = 'print_window_black (DirectComposition/UWP target; screenshot unreliable - use dispatch=foreground for a full render)' }
      if ([DshWin32]::IsIconic($win.Hwnd)) { $shot.error = 'window_minimized; screenshot is blank' }
    } else {
      $shot = @{ path = $null; width = 0; height = 0; scale = 1; error = 'print_window_failed' }
    }
  }
  $tree = Get-AccessibilityTree $win.Hwnd
  $docText = Get-DocumentText $win.Hwnd
  return @{
    window = (Get-WindowInfo $win)
    screenshot = $shot
    elements = $tree
    element_count = $tree.Count
    document_text = if ($docText) { $docText } else { '' }
    note = 'Element indexes are only valid together with this state; refresh after any UI change.'
  }
}

# ---------------------------------------------------------------- actions

$script:payload = $null
if ($PayloadJson) { $script:payload = $PayloadJson | ConvertFrom-Json }

$result = @{ ok = $true; action = $Action; message = '' }

try {
  switch ($Action) {
    'list_apps' {
      $wins = @([DshWin32]::EnumWindowsList())
      $byPid = @{}
      foreach ($w in $wins) {
        if ($w.Rect.Left -lt -10000 -or $w.Rect.Top -lt -10000) { continue }
        if (-not $byPid.ContainsKey($w.Pid)) {
          $pinfo = Get-Process -Id $w.Pid -ErrorAction SilentlyContinue
          $name = if ($pinfo) { $pinfo.ProcessName } else { "pid:$($w.Pid)" }
          $byPid[$w.Pid] = @{ pid = $w.Pid; name = $name; windows = New-Object System.Collections.ArrayList }
        }
        $null = $byPid[$w.Pid].windows.Add((Get-WindowInfo $w))
      }
      $result.apps = @($byPid.Values)
      $result.message = "Found $($byPid.Count) apps / $($wins.Count) windows"
    }

    'get_app_state' {
      $app = Get-PayloadValue 'app'
      $idx = [int](Get-PayloadValue 'window_index')
      $shot = Get-PayloadValue 'screenshot'
      if ($null -eq $shot) { $shot = $true }
      $st = Do-AppState -App $app -WindowIndex $idx -WithScreenshot ([bool]$shot) -Dispatch (Get-Dispatch)
      $result.window = $st.window
      $result.screenshot = $st.screenshot
      $result.elements = $st.elements
      $result.element_count = $st.element_count
      $result.document_text = $st.document_text
      $result.note = $st.note
      $result.dispatch = (Get-Dispatch)
      $result.message = "State captured for '$app' ($($st.element_count) elements)"
    }

    'click' {
      $app = Get-PayloadValue 'app'
      $x = [int](Get-PayloadValue 'x')
      $y = [int](Get-PayloadValue 'y')
      $dispatch = Get-Dispatch
      $win = $null
      if ($app) {
        $win = Resolve-TargetWindow -App $app -Index ([int](Get-PayloadValue 'window_index'))
        if ($dispatch -eq 'foreground') { [DshWin32]::ForceForeground($win.Hwnd) }
        $r = $win.Rect
        $sx = $r.Left + $x; $sy = $r.Top + $y
        if ($dispatch -eq 'foreground') { $result.focus_ok = ([DshWin32]::ForegroundHwnd() -eq $win.Hwnd.ToInt64()) }
      } else {
        $sx = $x; $sy = $y
      }
      if ($dispatch -eq 'background') {
        Notify-Cursor -X $sx -Y $sy -Label 'click'
        $hit = Invoke-FromPoint -X $sx -Y $sy
        if ($hit.ok) {
          $result.method = 'uia_hit_' + $hit.method
          $result.hit_name = $hit.name
          $result.message = "Background click at ($sx, $sy) -> $($hit.method) on '$($hit.name)'"
        } else {
          $result.background_unavailable = $true
          $result.message = "Background click at ($sx, $sy): no invokable/toggle/selectable control at that point (canvas or coordinate-text click). Use dispatch=foreground for a real click, or click_element with an element index."
        }
        $result.clicked = @{ x = $sx; y = $sy }
      } else {
        [DshWin32]::MouseClick($sx, $sy)
        $result.message = "Clicked at screen ($sx, $sy)"
        $result.clicked = @{ x = $sx; y = $sy }
      }
    }

    'click_element' {
      $app = Get-PayloadValue 'app'
      $element = [int](Get-PayloadValue 'element')
      $dispatch = Get-Dispatch
      $win = Resolve-TargetWindow -App $app -Index ([int](Get-PayloadValue 'window_index'))
      if ($dispatch -eq 'foreground') {
        [DshWin32]::ForceForeground($win.Hwnd)
        Start-Sleep -Milliseconds 150
        $result.focus_ok = ([DshWin32]::ForegroundHwnd() -eq $win.Hwnd.ToInt64())
      }
      $el = Find-ElementByIndex -Hwnd $win.Hwnd -Index $element
      $ip = $null
      if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) {
        if ($dispatch -eq 'background') { Notify-Cursor -X ([int]($el.Current.BoundingRectangle.X + $el.Current.BoundingRectangle.Width / 2)) -Y ([int]($el.Current.BoundingRectangle.Y + $el.Current.BoundingRectangle.Height / 2)) -Label ('click element ' + $element) }
        $ip.Invoke()
        $result.method = 'invoke_pattern'
        $result.message = "Invoked element $element"
      } else {
        $tog = $null
        if ($el.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$tog)) {
          $tog.Toggle(); $result.method = 'toggle_pattern'; $result.message = "Toggled element $element"
        } else {
          $sel = $null
          if ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) {
            $sel.Select(); $result.method = 'selection_pattern'; $result.message = "Selected element $element"
          } else {
            $exp = $null
            if ($el.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$exp)) {
              $exp.Expand(); $result.method = 'expand_pattern'; $result.message = "Expanded element $element"
            } elseif ($dispatch -eq 'background') {
              $r = $el.Current.BoundingRectangle
              $result.background_unavailable = $true
              $result.element_rect = @{ x = [int]$r.X; y = [int]$r.Y; width = [int]$r.Width; height = [int]$r.Height }
              $result.message = "Element $element has no UIA action pattern (Invoke/Toggle/Selection/ExpandCollapse); background click unavailable. Use dispatch=foreground."
            } else {
              $pt = New-Object System.Windows.Point
              $clickable = $el.TryGetClickablePoint([ref]$pt)
              if ($clickable) {
                [DshWin32]::MouseClick([int]$pt.X, [int]$pt.Y)
                $result.method = 'clickable_point'
                $result.message = "Clicked element $element at ($([int]$pt.X), $([int]$pt.Y))"
                $result.clicked = @{ x = [int]$pt.X; y = [int]$pt.Y }
              } else {
                $r2 = $el.Current.BoundingRectangle
                if ($r2.Width -gt 0 -and $r2.Height -gt 0) {
                  $cx = [int]($r2.X + $r2.Width / 2); $cy = [int]($r2.Y + $r2.Height / 2)
                  [DshWin32]::MouseClick($cx, $cy)
                  $result.method = 'rect_center'
                  $result.message = "Clicked element $element center at ($cx, $cy)"
                  $result.clicked = @{ x = $cx; y = $cy }
                } else {
                  throw 'element_not_clickable: element has no clickable point or frame'
                }
              }
            }
          }
        }
      }
    }

    'set_value' {
      $app = Get-PayloadValue 'app'
      $element = [int](Get-PayloadValue 'element')
      $value = Get-PayloadValue 'value'
      $dispatch = Get-Dispatch
      $win = Resolve-TargetWindow -App $app -Index ([int](Get-PayloadValue 'window_index'))
      if ($dispatch -eq 'foreground') {
        [DshWin32]::ForceForeground($win.Hwnd)
        Start-Sleep -Milliseconds 150
        $result.focus_ok = ([DshWin32]::ForegroundHwnd() -eq $win.Hwnd.ToInt64())
      }
      $el = Find-ElementByIndex -Hwnd $win.Hwnd -Index $element
      $vp = $null
      if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
        if ($dispatch -eq 'background') { Notify-Cursor -X ([int]($el.Current.BoundingRectangle.X + $el.Current.BoundingRectangle.Width / 2)) -Y ([int]($el.Current.BoundingRectangle.Y + $el.Current.BoundingRectangle.Height / 2)) -Label 'set_value' }
        $vp.SetValue($value)
        $result.method = 'value_pattern'
        $result.message = "Set element $element value"
      } elseif ($dispatch -eq 'background') {
        $result.background_unavailable = $true
        $result.message = "Element $element has no ValuePattern; background set_value unavailable. Use dispatch=foreground (focus_type) or type instead."
      } else {
        $el.SetFocus()
        Start-Sleep -Milliseconds 100
        [DshWin32]::TypeText($value)
        $result.method = 'focus_type'
        $result.message = 'Focused element and typed value (unverified)'
      }
    }

    'type' {
      $app = Get-PayloadValue 'app'
      $text = Get-PayloadValue 'text'
      $dispatch = Get-Dispatch
      if ($app) {
        $win = Resolve-TargetWindow -App $app -Index ([int](Get-PayloadValue 'window_index'))
        if ($dispatch -eq 'foreground') {
          [DshWin32]::ForceForeground($win.Hwnd)
          Start-Sleep -Milliseconds 150
          $result.focus_ok = ([DshWin32]::ForegroundHwnd() -eq $win.Hwnd.ToInt64())
        }
        $pt = Get-OverlayPoint-WindowCenter $win
        $cx = $pt[0]; $cy = $pt[1]
        if ($dispatch -eq 'background') {
          $h = Find-TextInputHwnd $win.Hwnd
          if ($h -eq [IntPtr]::Zero) {
            # fallback: apps with no native edit HWND (WinUI/Chromium) -> ValuePattern.SetValue
            $vel = Find-ValuePatternEl $win.Hwnd
            if ($null -ne $vel) {
              Notify-Cursor -X $cx -Y $cy -Label ('set_value ' + $text.Length + ' chars')
              $vv = $null
              if ($vel.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vv)) {
                $vv.SetValue($text)
                $result.method = 'value_pattern'
                $result.message = "Set text via ValuePattern ($(($text.Length)) chars) — WinUI/Chromium target with no edit HWND; replaces field content. Verify with get_app_state."
                break
              }
            }
            $result.background_unavailable = $true
            $result.message = "type: no edit HWND or ValuePattern control for WM_CHAR in '$app'; use dispatch=foreground."
            break
          }
          Notify-Cursor -X $cx -Y $cy -Label ("type " + $text.Length + ' chars')
          Send-BackgroundText -Hwnd $h -Text $text
          $result.method = 'wm_char'
          $result.target_hwnd = $h.ToInt64()
          $result.message = "Delivered $($text.Length) chars via WM_CHAR to hwnd $($h.ToInt64()) (verify with get_app_state)"
          break
        }
      }
      [DshWin32]::TypeText($text)
      $result.message = "Typed $($text.Length) characters"
    }

    'key' {
      $app = Get-PayloadValue 'app'
      $key = Get-PayloadValue 'key'
      $mods = Get-PayloadValue 'modifiers'
      $dispatch = Get-Dispatch
      $win = $null
      if ($app) {
        $win = Resolve-TargetWindow -App $app -Index ([int](Get-PayloadValue 'window_index'))
        if ($dispatch -eq 'foreground') {
          [DshWin32]::ForceForeground($win.Hwnd)
          Start-Sleep -Milliseconds 150
          $result.focus_ok = ([DshWin32]::ForegroundHwnd() -eq $win.Hwnd.ToInt64())
        }
      }
      if ($dispatch -eq 'background' -and $null -ne $win) {
        $h = Find-TextInputHwnd $win.Hwnd
        if ($h -eq [IntPtr]::Zero) {
          $result.background_unavailable = $true
          $result.message = "key: no focusable control HWND in '$app' to receive WM_KEY; use dispatch=foreground."
          break
        }
        $pt = Get-OverlayPoint-WindowCenter $win
        Notify-Cursor -X $pt[0] -Y $pt[1] -Label ('key ' + $key)
        Send-BackgroundKey -Hwnd $h -Key $key -Modifiers $mods
        $result.method = 'wm_key'
        $result.message = "Sent $key (wm_key) to hwnd $($h.ToInt64()); accelerator/menu handling is app-dependent"
        break
      }
      [DshWin32]::KeyChord($key, $mods)
      $result.message = "Pressed $key"
    }

    'scroll' {
      $app = Get-PayloadValue 'app'
      $x = [int](Get-PayloadValue 'x')
      $y = [int](Get-PayloadValue 'y')
      $amount = [int](Get-PayloadValue 'amount')
      if ($amount -le 0) { $amount = 3 }
      $dir = Get-PayloadValue 'direction'
      if (-not $dir) { $dir = 'down' }
      $down = ($dir -ne 'up')
      $dispatch = Get-Dispatch
      $win = $null
      if ($app) {
        $win = Resolve-TargetWindow -App $app -Index ([int](Get-PayloadValue 'window_index'))
        if ($dispatch -eq 'foreground') { [DshWin32]::ForceForeground($win.Hwnd) }
        $r = $win.Rect
        $sx = $r.Left + $x; $sy = $r.Top + $y
      } else {
        $sx = $x; $sy = $y
      }
      if ($dispatch -eq 'background') {
        Notify-Cursor -X $sx -Y $sy -Label ('scroll ' + $dir)
        $pt = New-Object System.Windows.Point($sx, $sy)
        $el = [System.Windows.Automation.AutomationElement]::FromPoint($pt)
        $done = $false
        for ($i = 0; $i -lt 8 -and $null -ne $el; $i++) {
          $rvp = $null
          if ($el.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rvp)) {
            for ($n = 0; $n -lt $amount; $n++) { if ($down) { $rvp.SmallIncrement() } else { $rvp.SmallDecrement() } }
            $result.method = 'range_value'; $done = $true; break
          }
          $scp = $null
          if ($el.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$scp)) {
            $none = [System.Windows.Automation.ScrollAmount]::NoAmount
            $amt = [System.Windows.Automation.ScrollAmount]::SmallIncrement
            for ($n = 0; $n -lt $amount; $n++) { if ($down) { $scp.Scroll($none, $amt) } else { $scp.Scroll($none, [System.Windows.Automation.ScrollAmount]::SmallDecrement) } }
            $result.method = 'scroll_pattern'; $done = $true; break
          }
          $el = $el.GetParent()
        }
        if (-not $done) {
          $ptStruct = New-Object DshWin32+POINT
          $ptStruct.X = $sx; $ptStruct.Y = $sy
          $h = [DshWin32]::WindowFromPoint($ptStruct)
          if ($h -ne [IntPtr]::Zero) {
            $delta = $amount * 120
            if ($down) { $delta = -$delta }
            $wParam = [IntPtr]($delta -shl 16)
            $lParam = [IntPtr](($sy -band 0xFFFF) -shl 16 -bor ($sx -band 0xFFFF))
            $null = [DshWin32]::SendMessage($h, 0x020A, $wParam, $lParam)
            $result.method = 'wm_mousewheel'
            $result.message = "Scrolled $dir x$amount via WM_MOUSEWHEEL to hwnd $($h.ToInt64())"
          } else {
            $result.background_unavailable = $true
            $result.message = 'scroll: no window under the point; nothing to scroll'
          }
        } else {
          $result.message = "Scrolled $dir x$amount via $($result.method)"
        }
      } else {
        [DshWin32]::Scroll($sx, $sy, $amount, $down)
        $result.message = "Scrolled $dir x$amount at ($sx, $sy)"
      }
    }

    'drag' {
      $app = Get-PayloadValue 'app'
      $dispatch = Get-Dispatch
      $win = $null
      if ($app) {
        $win = Resolve-TargetWindow -App $app -Index ([int](Get-PayloadValue 'window_index'))
        if ($dispatch -eq 'foreground') { [DshWin32]::ForceForeground($win.Hwnd) }
        $r = $win.Rect
      }
      $fx = [int](Get-PayloadValue 'from_x'); $fy = [int](Get-PayloadValue 'from_y')
      $tx = [int](Get-PayloadValue 'to_x'); $ty = [int](Get-PayloadValue 'to_y')
      if ($win) {
        $fx += $r.Left; $fy += $r.Top; $tx += $r.Left; $ty += $r.Top
      }
      if ($dispatch -eq 'background') {
        Notify-Cursor -X $fx -Y $fy -Label 'drag'
        $pt = New-Object System.Windows.Point($fx, $fy)
        $el = [System.Windows.Automation.AutomationElement]::FromPoint($pt)
        $tp = $null
        $moved = $false
        for ($i = 0; $i -lt 8 -and $null -ne $el; $i++) {
          if ($el.TryGetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern, [ref]$tp) -and $tp.Current.CanMove) {
            $rc = $el.Current.BoundingRectangle
            $newX = $rc.X + ($tx - $fx)
            $newY = $rc.Y + ($ty - $fy)
            $tp.Move($newX, $newY)
            $result.method = 'transform_move'
            $result.message = 'Dragged element via TransformPattern.Move (background)'
            $moved = $true
            break
          }
          $el = $el.GetParent()
        }
        if (-not $moved) {
          $result.background_unavailable = $true
          $result.message = 'drag: no movable (TransformPattern) element at the start point; background drag unavailable. Use dispatch=foreground (real input).'
        }
      } else {
        [DshWin32]::Drag($fx, $fy, $tx, $ty)
        $result.message = "Dragged ($fx,$fy) -> ($tx,$ty)"
      }
    }

    'open_app' {
      $name = Get-PayloadValue 'name'
      if (-not $name) { throw 'open_app requires name' }
      $proc = Start-Process $name -PassThru
      Start-Sleep -Milliseconds 600
      $result.message = "Started $name"
      $result.pid = $proc.Id
    }

    default {
      throw "unknown action: $Action"
    }
  }
}
catch {
  $result.ok = $false
  $result.message = "$($_.Exception.Message)"
}

[Console]::Out.Write(($result | ConvertTo-Json -Depth 10 -Compress))
