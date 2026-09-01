# dsh vc overlay — small click-through virtual MOUSE CURSOR for dsh-computer-use background mode.
# Shows a small pointer arrow at the AI current action point. It MOVES to each new
# point (never fades), is topmost, never activates, and all clicks pass through it.
# Reads %TEMP%\dsh-cua\cursor.state {x,y,ts,show} written by computer-use-helper.ps1.
param()
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# own pid so the one-shot helper can keep us alive
$dir = Join-Path $env:TEMP "dsh-cua"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path (Join-Path $dir "overlay.pid") -Value $PID -Encoding ascii

$asmWF  = [System.Windows.Forms.Form].Assembly.Location
$asmDraw = [System.Drawing.Bitmap].Assembly.Location
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
public class DshVcCur : Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams {
    get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x00000080; return cp; }
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x0084) { m.Result = (IntPtr)(-1); return; }  // HTTRANSPARENT: click-through
    base.WndProc(ref m);
  }
}
'@ -ReferencedAssemblies $asmWF, $asmDraw

$form = New-Object DshVcCur
$form.Size = New-Object System.Drawing.Size(22, 22)
$form.BackColor = [System.Drawing.Color]::Magenta
$form.TransparencyKey = [System.Drawing.Color]::Magenta
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.FormBorderStyle = "None"
$form.StartPosition = "Manual"
$form.Opacity = 0.0

# classic pointer arrow, tip at top-left (0,0), body extends down-right
$form.Add_Paint({
  param($s, $e)
  $g = $e.Graphics
  $g.SmoothingMode = "AntiAlias"
  $pts = @(
    (New-Object System.Drawing.PointF(1,1)),
    (New-Object System.Drawing.PointF(1,16)),
    (New-Object System.Drawing.PointF(5,12.5)),
    (New-Object System.Drawing.PointF(7,19)),
    (New-Object System.Drawing.PointF(9.5,18)),
    (New-Object System.Drawing.PointF(7,11.5)),
    (New-Object System.Drawing.PointF(12,11.5))
  )
  $fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
  $outline = New-Object System.Drawing.Pen ([System.Drawing.Color]::Black, 1.5)
  $g.FillPolygon($fill, $pts)
  $g.DrawPolygon($outline, $pts)
})

$stateFile = Join-Path $dir "cursor.state"
$script:lastTs = 0.0

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
  if (-not (Test-Path $stateFile)) { return }
  try {
    $st = Get-Content -Path $stateFile -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($null -ne $st -and $st.ts -and ([double]$st.ts -ne $script:lastTs)) {
      $script:lastTs = [double]$st.ts
      if ($st.show) {
        $form.Location = New-Object System.Drawing.Point([int][Math]::Round([double]$st.x), [int][Math]::Round([double]$st.y))
        $form.Opacity = 1.0
      } else {
        $form.Opacity = 0.0
      }
    }
  } catch { }
})

$form.Add_Shown({ $timer.Start() })
[System.Windows.Forms.Application]::Run($form)
