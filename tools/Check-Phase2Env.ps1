# Phase 2 environment check for the EA research workbench.
# READ-ONLY: only inspects the machine; changes nothing, uploads nothing.
# Run in PowerShell on the Windows PC that has MetaTrader 5:
#   powershell -ExecutionPolicy Bypass -File .\tools\Check-Phase2Env.ps1
$ErrorActionPreference = 'SilentlyContinue'
function Show($name, $val) { "{0,-28} {1}" -f $name, $val }

Show 'OS' ((Get-CimInstance Win32_OperatingSystem).Caption + ' ' + [Environment]::OSVersion.Version)
Show 'Node.js (REA needs ^22.19/^24.11/>=26)' (node -v 2>&1)
Show 'npm' (npm -v 2>&1)
Show 'Claude Code' (claude --version 2>&1)
Show 'Java (Ghidra needs JDK 21+)' ((java -version 2>&1 | Select-Object -First 1))
Show 'GHIDRA_INSTALL_DIR' ($(if ($env:GHIDRA_INSTALL_DIR) { $env:GHIDRA_INSTALL_DIR } else { '(not set)' }))

"`n--- MetaTrader 5 terminals (terminal64.exe) ---"
$roots = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:APPDATA\MetaQuotes\Terminal")
foreach ($r in $roots) {
  Get-ChildItem $r -Filter terminal64.exe -Recurse -Depth 3 | ForEach-Object {
    Show 'terminal64.exe' $_.FullName
    Show '  version' $_.VersionInfo.ProductVersion
  }
}

"`n--- MT5 data folders (EA files: counts only, names not read) ---"
Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory | ForEach-Object {
  $ex = Join-Path $_.FullName 'MQL5\Experts'
  if (Test-Path $ex) {
    $f = Get-ChildItem $ex -Recurse -File
    Show $_.Name ("ex5={0} mq5={1} mqh={2} set={3}" -f `
      ($f | ? Extension -eq '.ex5').Count, ($f | ? Extension -eq '.mq5').Count, `
      ($f | ? Extension -eq '.mqh').Count, ($f | ? Extension -eq '.set').Count)
  }
}
"`nNote: run MT5 Strategy Tester on a DEMO/offline account only."
