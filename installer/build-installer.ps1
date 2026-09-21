$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$issFile = Join-Path $PSScriptRoot 'TodoList.iss'

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -eq $flutterCommand) {
    throw '找不到 flutter 命令。请先配置 Flutter PATH，或在当前 PowerShell 中临时加入 Flutter SDK bin 目录。'
}

Push-Location $projectRoot
try {
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter build windows --release
}
finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $releaseDir 'todolist.exe'))) {
    throw "Windows Release 构建不存在：$releaseDir"
}

$isccCandidates = @(
    'C:\Program Files (x86)\Inno Setup 7\ISCC.exe',
    'C:\Program Files\Inno Setup 7\ISCC.exe'
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -eq $iscc) {
    throw '找不到 Inno Setup 7 的 ISCC.exe。请确认已安装 Inno Setup 7，并重新运行此脚本。'
}

& $iscc "/DMyAppVersion=1.0.0" $issFile
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup 构建失败，退出码：$LASTEXITCODE"
}

Write-Host "安装包已生成到：$(Join-Path $PSScriptRoot 'output')" -ForegroundColor Green
