# dsh vc overlay — virtual-cursor overlay for dsh-computer-use background mode.
# Transparent, click-through, never-activating layered window (codex-style cursor
# indicator). Reads %TEMP%\dsh-cua\cursor.state {x,y,label,ts,show} written by
# computer-use-helper.ps1 before each input action. x button hides (writes show:false).
param()
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# own pid so the one-shot helper can keep us alive
$dir = Join-Path $env:TEMP 'dsh-cua'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path (Join-Path $dir 'overlay.pid') -Value $PID -Encoding ascii

$asmWF  = [System.Windows.Forms.Form].Assembly.Location
$asmDraw = [System.Drawing.Bitmap].Assembly.Location
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
public class DshVcForm : Form {
  public static Rectangle Hit = new Rectangle(146, 2, 16, 16);
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams {
    get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x00000080; return cp; }
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x0084) {
      int x = (short)((int)m.LParam & 0xFFFF);
      int y = (short)((int)m.LParam >> 16);
      if (!Hit.Contains(PointToClient(new Point(x, y)))) { m.Result = (IntPtr)(-1); return; }
    }
    base.WndProc(ref m);
  }
}
'@ -ReferencedAssemblies $asmWF, $asmDraw

$stateFile = Join-Path $dir 'cursor.state'

$form = New-Object DshVcForm
$form.Text = 'dsh-vc-overlay'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.Size = New-Object System.Drawing.Size(164, 52)
$form.BackColor = [System.Drawing.Color]::Magenta
$form.TransparencyKey = [System.Drawing.Color]::Magenta
$form.Opacity = 0.0

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(0, 0)
$panel.Size = $form.ClientSize
$panel.BackColor = [System.Drawing.Color]::FromArgb(245, 30, 34, 44)

$icon = New-Object System.Windows.Forms.Panel
$icon.Location = New-Object System.Drawing.Point(6, 6)
$icon.Size = New-Object System.Drawing.Size(40, 40)
$icon.BackColor = [System.Drawing.Color]::Transparent
$icon.Add_Paint({
  param($s, $e)
  $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
  $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 64, 158, 255))
  $g.FillEllipse($brush, 4, 4, 32, 32)
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, 2.5)
  $pen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, 2.0)
  $g.DrawEllipse($pen, 4, 4, 32, 32)
  $g.DrawLine($pen, 20, 20, 40, 20)
  $g.DrawLine($pen2, 40, 20, 33, 17)
  $g.DrawLine($pen2, 40, 20, 37, 27)
})

$lbl = New-Object System.Windows.Forms.Label
$lbl.Location = New-Object System.Drawing.Point(50, 4)
$lbl.Size = New-Object System.Drawing.Size(108, 22)
$lbl.ForeColor = [System.Drawing.Color]::White
$lbl.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Bold)
$lbl.Text = 'click'

$pos = New-Object System.Windows.Forms.Label
$pos.Location = New-Object System.Drawing.Point(50, 26)
$pos.Size = New-Object System.Drawing.Size(108, 18)
$pos.ForeColor = [System.Drawing.Color]::FromArgb(255, 160, 170, 190)
$pos.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$pos.Text = '(0, 0)'

$btnHide = New-Object System.Windows.Forms.Button
$btnHide.Location = New-Object System.Drawing.Point(146, 2)
$btnHide.Size = New-Object System.Drawing.Size(16, 16)
$btnHide.FlatStyle = 'Flat'
$btnHide.FlatAppearance.BorderSize = 0
$btnHide.Text = 'x'
$btnHide.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$btnHide.ForeColor = [System.Drawing.Color]::White
$btnHide.BackColor = [System.Drawing.Color]::Transparent

$panel.Controls.Add($icon); $panel.Controls.Add($lbl); $panel.Controls.Add($pos); $panel.Controls.Add($btnHide)
$form.Controls.Add($panel)
[DshVcForm]::Hit = $btnHide.Bounds

$lastTs = 0.0
$shown = $false

$btnHide.Add_Click({
  $st = @{ x = 0; y = 0; label = 'hidden'; ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds(); show = $false } | ConvertTo-Json -Compress
  Set-Content -Path $stateFile -Value $st -Encoding ascii
  $form.Opacity = 0.0
  $script:shown = $false
})

function Show-Overlay([double]$x, [double]$y, [string]$label) {
  $sw = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $fx = [Math]::Round($x) + 14
  $fy = [Math]::Round($y) - 56
  if ($fx + $form.Width -gt $sw.Right)  { $fx = $sw.Right - $form.Width - 4 }
  if ($fy -lt $sw.Top)                  { $fy = [Math]::Round($y) + 16 }
  if ($fx -lt $sw.Left)                 { $fx = $sw.Left + 4 }
  $form.Location = New-Object System.Drawing.Point([int]$fx, [int]$fy)
  $lbl.Text = $label
  $pos.Text = ('({0}, {1})' -f [int][Math]::Round($x), [int][Math]::Round($y))
  $form.Opacity = 1.0
  $script:shown = $true
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
  if (-not (Test-Path $stateFile)) { return }
  try {
    $st = Get-Content -Path $stateFile -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($null -ne $st -and $st.ts -and $st.ts -ne $script:lastTs) {
      $script:lastTs = [double]$st.ts
      if ($st.show) {
        $label = if ($st.label) { [string]$st.label } else { 'operating' }
        Show-Overlay ([double]$st.x) ([double]$st.y) $label
        $fade.Stop(); $fade.Start()
      } else {
        $form.Opacity = 0.0
        $script:shown = $false
      }
    }
  } catch { }
})

$fade = New-Object System.Windows.Forms.Timer
$fade.Interval = 300
$fade.Add_Tick({
  if ($form.Opacity -gt 0.05) { $form.Opacity -= 0.05 }
  else { $form.Opacity = 0.0; $script:shown = $false; $fade.Stop() }
})

$form.Add_Shown({ $timer.Start() })
[System.Windows.Forms.Application]::Run($form)
