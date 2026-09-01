# dsh-computer-use smoke test: 只读动作，不移动鼠标、不按键。
# 用法: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/smoke-test.ps1
#       （也兼容 powershell.exe 5.1，但建议用 pwsh 7）
$helper = Join-Path $PSScriptRoot "..\lib\computer-use-helper.ps1"
$ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

function Get-HelperJson($lines, [string]$step) {
  $candidates = @()
  foreach ($item in $lines) {
    $s = if ($item -is [System.Management.Automation.ErrorRecord]) { $item.ToString() } else { [string]$item }
    if ($s -match '^\s*\{') { $candidates += $s }
  }
  $joined = $candidates -join "`n"
  $m = [regex]::Match($joined, '\{.*\}', 'Singleline')
  if (-not $m.Success) { throw "${step}: no JSON in helper output: $joined" }
  return $m.Value | ConvertFrom-Json
}

$oldEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"   # native 调用期间不因 stderr 抛错

Write-Host "== list_apps =="
$out1 = & $ps -NoProfile -ExecutionPolicy Bypass -File $helper -Action list_apps -PayloadJson '{}' 2>$null
$r1 = Get-HelperJson $out1 'list_apps'
if ($r1.ok -ne $true) { throw "list_apps failed: $($r1.message)" }
Write-Host ("OK: found {0} apps" -f @($r1.apps).Count)

Write-Host "== get_app_state (explorer, no screenshot) =="
$payload = @{ app = "explorer"; screenshot = $false } | ConvertTo-Json -Compress
$out2 = & $ps -NoProfile -ExecutionPolicy Bypass -File $helper -Action get_app_state -PayloadJson $payload 2>$null
$r2 = Get-HelperJson $out2 'get_app_state'
if ($r2.ok -ne $true) { throw "get_app_state failed: $($r2.message)" }
Write-Host ("OK: {0} elements" -f $r2.element_count)

$ErrorActionPreference = $oldEAP
Write-Host "smoke test passed."
