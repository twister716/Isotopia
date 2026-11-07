# CurseForgeアプリの記録 (minecraftinstance.json) を正解として、
# mods フォルダの jar と .pw.toml をそろえるスクリプト
#
#   1. 記録にあるのに .pw.toml が無いMod      → .pw.toml を作る
#   2. Modが更新されていた (file-idが違う)    → .pw.toml を書き直す
#   3. 記録から消えたModの .pw.toml           → 削除する
#   4. jar が無いMod                          → CurseForgeからダウンロードする
#   5. 最後に packwiz refresh で index.toml を更新する

$ErrorActionPreference = "Stop"
$instance = Split-Path -Parent $PSScriptRoot
$modsDir = Join-Path $instance "mods"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

$json = Get-Content (Join-Path $instance "minecraftinstance.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$addons = $json.installedAddons

# 既存の .pw.toml を project-id ごとに読み込む
$tomls = @{}
foreach ($t in Get-ChildItem $modsDir -Filter *.pw.toml) {
    $text = [System.IO.File]::ReadAllText($t.FullName)
    if ($text -match 'project-id\s*=\s*(\d+)') {
        $projectId = $Matches[1]
        $fileId = if ($text -match 'file-id\s*=\s*(\d+)') { $Matches[1] } else { "" }
        $tomls[$projectId] = @{ Path = $t.FullName; FileId = $fileId }
    }
}

function Escape-Toml([string]$s) {
    return $s.Replace('\', '\\').Replace('"', '\"')
}

$created = @(); $updated = @(); $removed = @(); $downloaded = @(); $failed = @()
$projectIds = @{}

foreach ($addon in $addons) {
    $file = $addon.installedFile
    $projectId = [string]$addon.addonID
    $projectIds[$projectId] = $true
    $sha1 = ($file.hashes | Where-Object { $_.type -eq 1 } | Select-Object -First 1).value

    # ---- .pw.toml を作る / 書き直す ----
    $content = @"
name = "$(Escape-Toml $addon.name)"
filename = "$(Escape-Toml $file.fileNameOnDisk)"
side = "both"

[download]
hash-format = "sha1"
hash = "$sha1"
mode = "metadata:curseforge"

[update]
[update.curseforge]
file-id = $($file.id)
project-id = $projectId

"@ -replace "`r`n", "`n"

    if (-not $tomls.ContainsKey($projectId)) {
        # ファイル名はCurseForgeのURL末尾 (例: applied-energistics-2) を使う
        $slug = ($addon.webSiteURL.TrimEnd('/') -split '/')[-1]
        $path = Join-Path $modsDir "$slug.pw.toml"
        [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
        $created += $addon.name
    }
    elseif ($tomls[$projectId].FileId -ne [string]$file.id) {
        [System.IO.File]::WriteAllText($tomls[$projectId].Path, $content, $utf8NoBom)
        $updated += $addon.name
    }

    # ---- jar が無ければダウンロード ----
    $jar = Join-Path $modsDir $file.fileNameOnDisk
    if (-not (Test-Path -LiteralPath $jar)) {
        try {
            Invoke-WebRequest -Uri $file.downloadUrl -OutFile $jar -UseBasicParsing
            if ((Get-FileHash -LiteralPath $jar -Algorithm SHA1).Hash.ToLower() -ne $sha1) {
                Remove-Item -LiteralPath $jar
                throw "ハッシュが一致しません"
            }
            $downloaded += $file.fileNameOnDisk
        }
        catch {
            $failed += "$($file.fileNameOnDisk) : $($_.Exception.Message)"
        }
    }
}

# ---- 記録から消えたModの .pw.toml を削除 ----
foreach ($id in @($tomls.Keys)) {
    if (-not $projectIds.ContainsKey($id)) {
        $removed += Split-Path -Leaf $tomls[$id].Path
        Remove-Item -LiteralPath $tomls[$id].Path
    }
}

# ---- index.toml を更新 ----
Push-Location $instance
packwiz refresh
Pop-Location

# ---- 結果表示 ----
function Show-List($title, $items) {
    if ($items.Count -eq 0) { return }
    Write-Host "$title ($($items.Count)個)" -ForegroundColor Yellow
    $items | ForEach-Object { Write-Host "  $_" }
}

Write-Host ""
Show-List "作った .pw.toml" $created
Show-List "更新した .pw.toml" $updated
Show-List "削除した .pw.toml" $removed
Show-List "ダウンロードした jar" $downloaded
if ($failed.Count -gt 0) {
    Write-Host "失敗したもの:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

$jarCount = (Get-ChildItem $modsDir -Filter *.jar).Count
$tomlCount = (Get-ChildItem $modsDir -Filter *.pw.toml).Count
Write-Host ""
Write-Host "CurseForgeの記録: $($addons.Count) 個 / jar: $jarCount 個 / .pw.toml: $tomlCount 個" -ForegroundColor Cyan
