# 配布用のzipを作るスクリプト
#   1. パックのバージョンを決める（pack.toml を書き換える）
#   2. sync.ps1 を実行して、Modとconfigの最新の状態を index.toml に反映する
#   3. packwiz curseforge export で exports フォルダにzipを作る

$ErrorActionPreference = "Stop"
$instance = Split-Path -Parent $PSScriptRoot
$packToml = Join-Path $instance "pack.toml"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# ---- 1. バージョンを決める ----
$text = [System.IO.File]::ReadAllText($packToml)
$name = [regex]::Match($text, '(?m)^name = "(.*)"').Groups[1].Value
$current = [regex]::Match($text, '(?m)^version = "(.*)"').Groups[1].Value

Write-Host "今のバージョン: $current"
$version = Read-Host "出すバージョンを入力（そのままEnterで $current）"
if ($version -eq "") { $version = $current }

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Host "バージョンは 0.1.0 のように「数字.数字.数字」で入力してください" -ForegroundColor Red
    exit 1
}

if ($version -ne $current) {
    $text = [regex]::Replace($text, '(?m)^version = ".*"', "version = `"$version`"")
    [System.IO.File]::WriteAllText($packToml, $text, $utf8NoBom)
    Write-Host "pack.toml のバージョンを $version に変更しました"
}

# ---- 2. 最新の状態を反映する ----
Write-Host ""
Write-Host "Modとconfigの状態を同期しています..."
& (Join-Path $PSScriptRoot "sync.ps1")

# ---- 3. zipを作る ----
$exportDir = Join-Path $instance "exports"
New-Item -ItemType Directory -Force $exportDir | Out-Null
$zip = Join-Path $exportDir "$name-$version.zip"

if (Test-Path -LiteralPath $zip) {
    $answer = Read-Host "$name-$version.zip はもうあります。上書きしますか？ (y/n)"
    if ($answer -ne "y") { Write-Host "中止しました"; exit 0 }
    Remove-Item -LiteralPath $zip
}

Push-Location $instance
packwiz curseforge export -o $zip
Pop-Location

if (Test-Path -LiteralPath $zip) {
    Write-Host ""
    Write-Host "完成: exports\$name-$version.zip" -ForegroundColor Green
    explorer.exe /select,"$zip"
}
else {
    Write-Host "zipを作れませんでした。上のメッセージを確認してください" -ForegroundColor Red
}
