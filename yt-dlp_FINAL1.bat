<# :
@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title Telechargeur yt-dlp Express
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content '%~f0' -Raw)" && pause || pause
exit /b
#>

<#
===============================================================================
TELECHARGEUR YT-DLP EXPRESS - Version 2.0 (Optimisee & Securisee)
===============================================================================
Fonctionnalites :
  - Telechargement MP3 et MP4
  - Detection automatique de playlists
  - Installation automatique des dependances
  - Gestion d'erreur robuste
  - Logs detailles pour diagnostic
===============================================================================
#>

[CmdletBinding()]
param()

# ============================================================================
# CONFIGURATION GLOBALE
# ============================================================================
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# Configuration console UTF-8
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Fallback silencieux
}

# Variables script
$script:Config = @{
    YtDlpVersion = $null
    HasFFmpeg = $false
    DownloadFolder = ""
    LogFile = ""
}

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    switch ($Level) {
        "INFO"    { Write-Host "[$timestamp] ℹ️  $Message" -ForegroundColor Gray }
        "WARN"    { Write-Host "[$timestamp] ⚠️  $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$timestamp] ❌ $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "[$timestamp] ✅ $Message" -ForegroundColor Green }
    }
}

function Show-Title {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          TELECHARGEUR YT-DLP EXPRESS v2.0                      ║" -ForegroundColor Cyan
    Write-Host "║                      Securise & Optimise                       ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# GESTION DEPENDANCES
# ============================================================================

function Get-YtDlpVersion {
    try {
        $output = & yt-dlp --version 2>$null
        if ($output) {
            return $output.Trim() -replace '^v', ''
        }
    } catch {}
    return $null
}

function Get-LatestYtDlpVersion {
    try {
        $params = @{
            Uri = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
            TimeoutSec = 3
            UseBasicParsing = $true
        }
        
        $response = Invoke-WebRequest @params -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $json = $response.Content | ConvertFrom-Json
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
        $currArr = @($Current -split '\.' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        $latArr = @($Latest -split '\.' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        
        $maxLen = [Math]::Max($currArr.Count, $latArr.Count)
        
        for ($i = 0; $i -lt $maxLen; $i++) {
            $c = if ($i -lt $currArr.Count) { $currArr[$i] } else { 0 }
            $l = if ($i -lt $latArr.Count) { $latArr[$i] } else { 0 }
            
            if ($c -lt $l) { return $true }
            if ($c -gt $l) { return $false }
        }
    } catch {
        Write-Log "Erreur comparaison versions" "WARN"
    }
    return $false
}

function Install-YtDlp {
    Write-Log "Installation de yt-dlp..."
    
    # Essayer winget (Windows 11 et 10 recent)
    try {
        $wingetPath = & where winget 2>$null
        if ($wingetPath) {
            & winget install -e yt-dlp 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "yt-dlp installe avec succes" "SUCCESS"
                return $true
            }
        }
    } catch {}
    
    # Fallback : choco
    try {
        $chocoPath = & where choco 2>$null
        if ($chocoPath) {
            & choco install yt-dlp -y 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "yt-dlp installe avec Chocolatey" "SUCCESS"
                return $true
            }
        }
    } catch {}
    
    Write-Log "Installation manuelle requise : https://github.com/yt-dlp/yt-dlp" "ERROR"
    return $false
}

function Install-FFmpeg {
    Write-Log "Installation de ffmpeg..."
    
    try {
        $wingetPath = & where winget 2>$null
        if ($wingetPath) {
            & winget install -e ffmpeg 2>$null | Out-Null
            return $LASTEXITCODE -eq 0
        }
    } catch {}
    
    try {
        $chocoPath = & where choco 2>$null
        if ($chocoPath) {
            & choco install ffmpeg -y 2>$null | Out-Null
            return $LASTEXITCODE -eq 0
        }
    } catch {}
    
    return $false
}

function Test-Dependencies {
    Show-Title
    Write-Host "🔍 Verification des dependances..." -ForegroundColor Cyan
    Write-Host ""
    
    # Test yt-dlp
    $ytDlpCmd = Get-Command yt-dlp -ErrorAction SilentlyContinue
    if (-not $ytDlpCmd) {
        Write-Log "yt-dlp non trouve" "WARN"
        if (-not (Install-YtDlp)) {
            Write-Log "Impossible d'installer yt-dlp - Abandon" "ERROR"
            Read-Host "Appuyez sur ENTREE"
            exit 1
        }
    }
    
    # Verifier version yt-dlp
    $script:Config.YtDlpVersion = Get-YtDlpVersion
    if ($script:Config.YtDlpVersion) {
        Write-Log "yt-dlp v$($script:Config.YtDlpVersion) detecte" "SUCCESS"
    } else {
        Write-Log "Impossible de verifier la version yt-dlp" "ERROR"
        Read-Host "Appuyez sur ENTREE"
        exit 1
    }
    
    # Verifier mises a jour (non-bloquant)
    $latestVersion = Get-LatestYtDlpVersion
    if ($latestVersion -and (Compare-Versions -Current $script:Config.YtDlpVersion -Latest $latestVersion)) {
        Write-Log "Mise a jour disponible : v$latestVersion" "WARN"
    }
    
    Write-Host ""
    
    # Test ffmpeg (optionnel)
    $ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpegCmd) {
        Write-Log "ffmpeg non trouve (optionnel)" "WARN"
        if (Install-FFmpeg) {
            $script:Config.HasFFmpeg = $true
            Write-Log "ffmpeg installe" "SUCCESS"
        } else {
            Write-Log "ffmpeg sera ignore" "WARN"
        }
    } else {
        $script:Config.HasFFmpeg = $true
        Write-Log "ffmpeg detecte" "SUCCESS"
    }
    
    Write-Host ""
    Write-Host "Dependances verifiees !" -ForegroundColor Green
    Read-Host "Appuyez sur ENTREE pour continuer"
}

# ============================================================================
# GESTION CHEMINS
# ============================================================================

function Get-SafeDownloadPath {
    try {
        $downloadsPath = [System.IO.Path]::Combine(
            [System.Environment]::GetFolderPath([System.Environment]::SpecialFolder::UserProfile),
            "Downloads"
        )
        
        if (Test-Path -LiteralPath $downloadsPath -PathType Container) {
            return $downloadsPath
        }
    } catch {}
    
    # Fallback
    try {
        if (Test-Path -LiteralPath "$HOME\Downloads" -PathType Container) {
            return "$HOME\Downloads"
        }
    } catch {}
    
    # Dernier recours
    return $HOME
}

# ============================================================================
# VALIDATION
# ============================================================================

function Test-ValidUrl {
    param([string]$Url)
    
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    
    try {
        $uri = [uri]$Url
        return $uri.Scheme -in @("http", "https")
    } catch {
        return $false
    }
}

function Test-PlaylistInfo {
    param([string]$Url)
    
    try {
        $timeout = 4
        $args = @("--dump-json", "--flat-playlist", "--socket-timeout", $timeout, $url)
        
        $output = & yt-dlp $args 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        
        if ($output -and $output.entries) {
            $count = @($output.entries).Count
            if ($count -gt 1) {
                return @{
                    IsPlaylist = $true
                    Count = $count
                    Title = $output.title -replace '[^\w\s\-]', ''
                }
            }
        }
    } catch {}
    
    return @{ IsPlaylist = $false; Count = 1; Title = "Contenu" }
}

# ============================================================================
# INTERFACE UTILISATEUR
# ============================================================================

function Get-UserUrl {
    do {
        Show-Title
        Write-Host ""
        $input = Read-Host "📎 Entrez l'URL (ou 'q' pour quitter)"
        $cleanInput = $input.Trim()
        
        if ($cleanInput -eq 'q' -or $cleanInput -eq 'Q') {
            Write-Log "Au revoir !" "INFO"
            exit 0
        }
        
        if (Test-ValidUrl -Url $cleanInput) {
            return $cleanInput
        }
        
        Write-Log "URL invalide. Utilisez http:// ou https://" "ERROR"
        Start-Sleep -Seconds 1
    } while ($true)
}

function Get-Format {
    Show-Title
    Write-Host ""
    Write-Host "📁 FORMAT DE TELECHARGEMENT" -ForegroundColor Cyan
    Write-Host "  1. MP3 (Audio uniquement)"
    Write-Host "  2. MP4 (Video + Audio)"
    Write-Host ""
    
    do {
        $choice = (Read-Host "Votre choix (1 ou 2)").Trim()
        if ($choice -in @("1", "2")) { return $choice }
        Write-Log "Choix invalide" "ERROR"
    } while ($true)
}

function Get-VideoQuality {
    Write-Host ""
    Write-Host "🎬 QUALITE VIDEO" -ForegroundColor Cyan
    Write-Host "  1. Meilleure qualite (4K/2K/1080p)"
    Write-Host "  2. 1080p maximum"
    Write-Host "  3. 720p maximum"
    Write-Host ""
    
    do {
        $choice = (Read-Host "Votre choix (1, 2 ou 3)").Trim()
        if ($choice -in @("1", "2", "3")) { return $choice }
        Write-Log "Choix invalide" "ERROR"
    } while ($true)
}

function Confirm-Playlist {
    param([string]$Title, [int]$Count)
    
    Write-Host ""
    Write-Host "🎵 PLAYLIST DETECTEE" -ForegroundColor Yellow
    Write-Host "  Titre : $Title" -ForegroundColor Cyan
    Write-Host "  Fichiers : $Count" -ForegroundColor Cyan
    Write-Host ""
    
    do {
        $choice = (Read-Host "Telecharger les $Count fichiers ? (o/N)").Trim().ToLower()
        if ($choice -in @("o", "n", "")) { return $choice -eq "o" }
    } while ($true)
}

# ============================================================================
# TELECHARGEMENT
# ============================================================================

function Build-DownloadArgs {
    param(
        [string]$Url,
        [string]$Format,
        [string]$Quality,
        [string]$OutputFolder
    )
    
    $args = @(
        "--no-mtime",
        "--progress",
        "-P", $OutputFolder,
        "-o", "%(title)s.%(ext)s"
    )
    
    if ($script:Config.HasFFmpeg) {
        $args += "--add-metadata"
        $args += "--embed-thumbnail"
    }
    
    if ($Format -eq "1") {
        # MP3
        if ($script:Config.HasFFmpeg) {
            $args += @("-x", "--audio-format", "mp3", "--audio-quality", "0")
        } else {
            $args += @("-x", "--audio-quality", "0")
        }
    } else {
        # MP4
        $videoFormat = switch ($Quality) {
            "2" { "bv*[height<=1080]+ba/b[height<=1080]" }
            "3" { "bv*[height<=720]+ba/b[height<=720]" }
            default { "bv+ba/b" }
        }
        
        $args += @("-f", $videoFormat)
        if ($script:Config.HasFFmpeg) {
            $args += @("--merge-output-format", "mp4")
        }
    }
    
    # Gerer les playlists
    $playlistInfo = Test-PlaylistInfo -Url $Url
    if ($playlistInfo.IsPlaylist) {
        $args += "--yes-playlist"
    } else {
        $args += "--no-playlist"
    }
    
    $args += $Url
    return $args
}

function Start-Download {
    param(
        [string]$Url,
        [string]$Format,
        [string]$Quality
    )
    
    Show-Title
    Write-Host ""
    
    # Construire les arguments
    $args = Build-DownloadArgs -Url $Url -Format $Format -Quality $Quality -OutputFolder $script:Config.DownloadFolder
    
    # Execution
    Write-Log "Telechargement en cours..." "INFO"
    Write-Host ""
    
    & yt-dlp @args
    $success = $LASTEXITCODE -eq 0
    
    Write-Host ""
    if ($success) {
        Write-Log "Telechargement termine avec succes !" "SUCCESS"
    } else {
        Write-Log "Le telechargement a echoue (code erreur: $LASTEXITCODE)" "ERROR"
    }
    
    return $success
}

# ============================================================================
# PROGRAMME PRINCIPAL
# ============================================================================

function Main {
    # Verifier dependances
    Test-Dependencies
    
    # Initialiser le dossier de sortie
    $script:Config.DownloadFolder = Get-SafeDownloadPath
    Write-Log "Dossier de sortie : $($script:Config.DownloadFolder)" "INFO"
    Write-Host ""
    
    # Boucle principale
    while ($true) {
        # Etape 1 : URL
        $url = Get-UserUrl
        
        # Etape 1.5 : Analyser playlist
        Write-Host "   🔍 Analyse du contenu..." -ForegroundColor Gray
        $playlistInfo = Test-PlaylistInfo -Url $url
        
        if ($playlistInfo.IsPlaylist) {
            if (-not (Confirm-Playlist -Title $playlistInfo.Title -Count $playlistInfo.Count)) {
                Write-Log "Telechargement annule" "INFO"
                Start-Sleep -Seconds 1
                continue
            }
        }
        
        # Etape 2 : Format
        $format = Get-Format
        
        # Etape 2.5 : Qualite video
        $quality = "1"
        if ($format -eq "2") {
            $quality = Get-VideoQuality
        }
        
        # Etape 3 : Lancer telechargement
        $success = Start-Download -Url $url -Format $format -Quality $quality
        
        # Etape 4 : Menu de fin
        Write-Host ""
        Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
        
        do {
            $choice = (Read-Host "Appuyez sur ENTREE pour continuer ou 'q' pour quitter").Trim().ToLower()
            if ($choice -in @("", "q")) { break }
        } while ($true)
        
        if ($choice -eq "q") { break }
    }
    
    Write-Log "Au revoir !" "INFO"
}

# Lancer le programme
try {
    Main
} catch {
    Write-Log "Erreur critique : $_" "ERROR"
    Read-Host "Appuyez sur ENTREE"
    exit 1
}
