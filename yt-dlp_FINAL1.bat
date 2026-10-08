<# :
@echo off
chcp 65001 >nul
setlocal
title Telechargeur yt-dlp Express
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)"
echo.
echo ======================================================
echo Le programme s'est arrete.
echo ======================================================
pause
exit /b
#>

# ----------------------------------------------------------------------
# CODE POWERSHELL NATIVE
# ----------------------------------------------------------------------

[CmdletBinding()]
param ()

# Configuration encodage console UTF-8
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# Variables globales pour cache
$script:ytDlpVersion = $null
$script:latestVersionChecked = $false
$script:lastVersionCheck = $null

function Get-YtDlpVersion {
    try {
        $versionOutput = & yt-dlp --version 2>$null
        if ($versionOutput) {
            return $versionOutput.Trim()
        }
    } catch {}
    return $null
}

function Get-LatestYtDlpVersion {
    try {
        $response = Invoke-WebRequest -Uri "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest" -TimeoutSec 4 -ErrorAction SilentlyContinue
        if ($response) {
            $json = $response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json.tag_name) {
                return $json.tag_name.TrimStart('v')
            }
        }
    } catch {}
    return $null
}

function Compare-Versions {
    param([string]$Current, [string]$Latest)
    
    if (-not $Current -or -not $Latest) { return $false }
    
    try {
        $current_arr = $Current.Split('.') | ForEach-Object { [int]$_ }
        $latest_arr = $Latest.Split('.') | ForEach-Object { [int]$_ }
        
        for ($i = 0; $i -lt [Math]::Max($current_arr.Count, $latest_arr.Count); $i++) {
            $c = if ($i -lt $current_arr.Count) { $current_arr[$i] } else { 0 }
            $l = if ($i -lt $latest_arr.Count) { $latest_arr[$i] } else { 0 }
            
            if ($c -lt $l) { return $true }
            if ($c -gt $l) { return $false }
        }
    } catch {}
    return $false
}

function Test-AndInstallDependency {
    Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   Verification des dependances...      ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $ytDlp = Get-Command yt-dlp -ErrorAction SilentlyContinue
    
    if (-not $ytDlp) {
        Write-Host "⏳ yt-dlp n'est pas installe..." -ForegroundColor Yellow
        Write-Host "   Installation en cours..." -ForegroundColor Gray
        
        try {
            & winget install yt-dlp -e -h 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ yt-dlp installe !" -ForegroundColor Green
            } else {
                Write-Host "✗ Echec de l'installation via winget." -ForegroundColor Red
                Write-Host "   Installez manuellement : https://github.com/yt-dlp/yt-dlp" -ForegroundColor Yellow
                return $false
            }
        } catch {
            Write-Host "✗ Winget n'est pas disponible." -ForegroundColor Red
            return $false
        }
    } else {
        $script:ytDlpVersion = Get-YtDlpVersion
        Write-Host "✓ yt-dlp detecte (v$($script:ytDlpVersion))" -ForegroundColor Green
        
        # Verifier et mettre a jour en arriere-plan (non-bloquant)
        Write-Host "   Verification des mises a jour..." -ForegroundColor Gray
        
        $latestVersion = Get-LatestYtDlpVersion
        
        if ($latestVersion -and (Compare-Versions -Current $script:ytDlpVersion -Latest $latestVersion)) {
            Write-Host "⏳ Mise a jour disponible (v$latestVersion)..." -ForegroundColor Yellow
            
            try {
                & winget upgrade yt-dlp -e -h 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $script:ytDlpVersion = Get-YtDlpVersion
                    Write-Host "✓ yt-dlp mis a jour (v$($script:ytDlpVersion)) !" -ForegroundColor Green
                } else {
                    Write-Host "⚠ Mise a jour echouee, utilisation v$($script:ytDlpVersion)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠ Impossible de mettre a jour, utilisation v$($script:ytDlpVersion)" -ForegroundColor Yellow
            }
        }
        
        $script:latestVersionChecked = $true
    }
    
    Write-Host ""
    
    # ffmpeg (silencieux, optionnel)
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        Write-Host "⏳ ffmpeg n'est pas installe..." -ForegroundColor Yellow
        Write-Host "   Installation en cours..." -ForegroundColor Gray
        
        try {
            & winget install ffmpeg -e -h 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ ffmpeg installe !" -ForegroundColor Green
            } else {
                Write-Host "⚠ ffmpeg non installe (optionnel)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠ ffmpeg non installe (optionnel)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✓ ffmpeg detecte" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Appuyez sur une touche pour continuer..." -ForegroundColor Cyan
    Read-Host | Out-Null
    
    return $true
}

function Get-UserDownloadPath {
    try {
        return [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment]::SpecialFolder::UserProfile), "Downloads")
    } catch {
        return [System.IO.Path]::Combine($HOME, "Downloads")
    }
}

function Test-IsValideUrl {
    param ([string]$InputUrl)
    if ([string]::IsNullOrWhiteSpace($InputUrl)) { return $false }
    [uri]$uriResult = $null
    return ([System.Uri]::TryCreate($InputUrl, [System.UriKind]::Absolute, [ref]$uriResult) -and 
            ($uriResult.Scheme -eq [System.Uri]::UriSchemeHttp -or $uriResult.Scheme -eq [System.Uri]::UriSchemeHttps))
}

function Get-PlaylistInfo {
    param ([string]$InputUrl, [int]$TimeoutSeconds = 5)
    
    try {
        $job = Start-Job -ScriptBlock {
            param($url)
            try {
                $output = & yt-dlp --dump-json --flat-playlist --socket-timeout 4 $url 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
                return $output
            } catch {
                return $null
            }
        } -ArgumentList $InputUrl
        
        $result = Wait-Job -Job $job -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
        
        if ($result) {
            $output = Receive-Job -Job $job
            Remove-Job -Job $job -Force
            
            if ($output -and $output.entries) {
                $count = @($output.entries).Count
                if ($count -gt 1) {
                    return @{
                        IsPlaylist = $true
                        Count = $count
                        Title = $output.title
                    }
                }
            }
        } else {
            Remove-Job -Job $job -Force
        }
    } catch {}
    
    return @{
        IsPlaylist = $false
        Count = 1
        Title = "Contenu"
    }
}

if (-not (Test-AndInstallDependency)) {
    return
}

$dossierSortie = Get-UserDownloadPath
$hasFFmpeg = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)

while ($true) {
    Clear-Host
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "    TELECHARGEUR YT-DLP EXPRESS" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    # Etape 1 : URL
    $url = ""
    do {
        $inputUrl = Read-Host "📎 Colle le lien (ou 'q' pour quitter)"
        $cleanInput = $inputUrl.Trim()

        if ($cleanInput -eq 'q') {
            return
        }

        if (Test-IsValideUrl -InputUrl $cleanInput) {
            $url = $cleanInput
        } else {
            Write-Host "❌ Lien invalide. Entrez une URL HTTP/HTTPS." -ForegroundColor Red
        }
    } until ($url -ne "")

    # Etape 1.5 : Verifier playlist RAPIDEMENT
    Write-Host "   🔍 Analyse..." -ForegroundColor Gray
    $playlistInfo = Get-PlaylistInfo -InputUrl $url -TimeoutSeconds 5
    
    if ($playlistInfo.IsPlaylist) {
        Write-Host "🎵 Ceci est une playlist" -ForegroundColor Yellow
        Write-Host "Titre : $($playlistInfo.Title)" -ForegroundColor Cyan
        Write-Host "Nombre de fichiers : $($playlistInfo.Count)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "   Playlist trouvee" -ForegroundColor Yellow
        Write-Host "   Titre : $($playlistInfo.Title)" -ForegroundColor Cyan
        Write-Host "   Nombre de fichiers : $($playlistInfo.Count)" -ForegroundColor Cyan
        Write-Host ""
        
        $confirmPlaylist = Read-Host "Telecharger les $($playlistInfo.Count) fichiers ? (o/N)"
        
        if ($confirmPlaylist.ToLower() -ne 'o') {
            Write-Host "   ❌ Telechargement annule." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            continue
        }
    }

    # Etape 2 : Format
    Write-Host ""
    Write-Host "📁 FORMAT :" -ForegroundColor Cyan
    Write-Host "  1. MP3 (Audio)"
    Write-Host "  2. MP4 (Video)"

    do {
        $formatChoix = (Read-Host "Choix (1 ou 2)").Trim()
    } until ($formatChoix -eq "1" -or $formatChoix -eq "2")

    # Etape 2.5 : Qualite Video
    $qualiteChoix = "1"
    if ($formatChoix -eq "2") {
        Write-Host ""
        Write-Host "🎬 QUALITE VIDEO :" -ForegroundColor Cyan
        Write-Host "  1. Max (4K/2K/1080p)"
        Write-Host "  2. 1080p max"
        Write-Host "  3. 720p max"

        do {
            $qualiteChoix = (Read-Host "Choix (1, 2 ou 3)").Trim()
        } until ($qualiteChoix -eq "1" -or $qualiteChoix -eq "2" -or $qualiteChoix -eq "3")
    }

    # Etape 3 : Arguments
    $arguments = @(
        "--yes-playlist",
        "--no-mtime",
        "-P", $dossierSortie,
        "-o", "%(title)s.%(ext)s"
    )

    if ($hasFFmpeg) {
        $arguments += "--add-metadata"
        $arguments += "--embed-thumbnail"
    }

    if ($formatChoix -eq "1") {
        if ($hasFFmpeg) {
            $arguments += @("-x", "--audio-format", "mp3", "--audio-quality", "0")
        } else {
            $arguments += @("-x", "--audio-quality", "0")
        }
    } else {
        switch ($qualiteChoix) {
            "2" { $videoFormat = "bv*[height<=1080]+ba/b[height<=1080]" }
            "3" { $videoFormat = "bv*[height<=720]+ba/b[height<=720]" }
            default { $videoFormat = "bv+ba/b" }
        }
        $arguments += @("-f", $videoFormat)
        if ($hasFFmpeg) { $arguments += @("--merge-output-format", "mp4") }
    }

    $arguments += $url

    # Etape 4 : Execution
    Write-Host ""
    Write-Host "⬇️  Telechargement en cours..." -ForegroundColor Green
    & yt-dlp @arguments
    $downloadSuccess = $LASTEXITCODE -eq 0

    if ($downloadSuccess) {
        Write-Host ""
        Write-Host "✅ Telechargement termine avec succes !" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "❌ Le telechargement a echoue." -ForegroundColor Red
    }

    Write-Host ""
    $action = Read-Host "Appuyez sur ENTREE pour continuer ou une autre touche pour quitter"
    if ($action.Trim() -ne '') { break }
}
