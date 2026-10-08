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

function Test-Dependency {
    $ytDlp = Get-Command yt-dlp -ErrorAction SilentlyContinue
    if (-not $ytDlp) {
        Write-Host "`n[ERREUR CRITIQUE] 'yt-dlp' n'est pas installe ou absent du PATH." -ForegroundColor Red
        Write-Host "Place yt-dlp.exe dans le meme dossier que ce script." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Get-UserDownloadPath {
    try {
        return [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile), "Downloads")
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

if (-not (Test-Dependency)) {
    return
}

$dossierSortie = Get-UserDownloadPath
$hasFFmpeg = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)

while ($true) {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       TELECHARGEUR YT-DLP EXPRESS      " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Etape 1 : URL
    $url = ""
    do {
        $inputUrl = Read-Host "Colle le lien (ou tape 'q' pour quitter)"
        $cleanInput = $inputUrl.Trim()

        if ($cleanInput -eq 'q') {
            return
        }

        if (Test-IsValideUrl -InputUrl $cleanInput) {
            $url = $cleanInput
        } else {
            Write-Host "Lien invalide. Entrez une URL HTTP/HTTPS." -ForegroundColor Red
        }
    } until ($url -ne "")

    # Etape 2 : Format
    Write-Host "`nFORMAT  :" -ForegroundColor Yellow
    Write-Host "1. MP3 (Audio)"
    Write-Host "2. MP4 (Video)"

    do {
        $formatChoix = (Read-Host "Choix (1 ou 2)").Trim()
    } until ($formatChoix -eq "1" -or $formatChoix -eq "2")

    # Etape 2.5 : Qualite Video
    $qualiteChoix = "1"
    if ($formatChoix -eq "2") {
        Write-Host "`nQUALITE VIDEO :" -ForegroundColor Yellow
        Write-Host "1. Max (4K/2K/1080p)"
        Write-Host "2. 1080p max"
        Write-Host "3. 720p max"

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
    Write-Host "`nTelechargement en cours..." -ForegroundColor Green
    & yt-dlp @arguments

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nTelechargement termine avec succes !" -ForegroundColor Green
    } else {
        Write-Host "`n[ERREUR] Le telechargement a echoue." -ForegroundColor Red
    }

    Write-Host ""
    $action = Read-Host "[Entree] Recommencer | [Autre touche] Quitter"
    if ($action.Trim() -ne '') { break }
}