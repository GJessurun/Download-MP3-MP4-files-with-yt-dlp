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

function Test-AndInstallDependency {
    Write-Host "Verification des dependances..." -ForegroundColor Cyan
    
    # Verifier yt-dlp
    $ytDlp = Get-Command yt-dlp -ErrorAction SilentlyContinue
    if (-not $ytDlp) {
        Write-Host "`n[INFO] yt-dlp n'est pas installe. Installation en cours..." -ForegroundColor Yellow
        try {
            & winget install yt-dlp -e -h 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] yt-dlp installe avec succes." -ForegroundColor Green
                $ytDlp = Get-Command yt-dlp -ErrorAction SilentlyContinue
            } else {
                Write-Host "[ERREUR] Impossible d'installer yt-dlp via winget." -ForegroundColor Red
                Write-Host "Veuillez installer manuellement depuis https://github.com/yt-dlp/yt-dlp" -ForegroundColor Yellow
                return $false
            }
        } catch {
            Write-Host "[ERREUR] Winget n'est pas disponible ou ne fonctionne pas." -ForegroundColor Red
            Write-Host "Installez yt-dlp manuellement ou installez winget d'abord." -ForegroundColor Yellow
            return $false
        }
    }
    
    # Verifier ffmpeg
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        Write-Host "`n[INFO] ffmpeg n'est pas installe. Installation en cours..." -ForegroundColor Yellow
        try {
            & winget install ffmpeg -e -h 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] ffmpeg installe avec succes." -ForegroundColor Green
            } else {
                Write-Host "[AVERTISSEMENT] ffmpeg n'a pas pu etre installe." -ForegroundColor Yellow
                Write-Host "Les fonctionnalites de video seront limitees." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[AVERTISSEMENT] Impossible d'installer ffmpeg via winget." -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
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

function Get-PlaylistInfo {
    param ([string]$InputUrl, [int]$TimeoutSeconds = 8)
    
    Write-Host "Analyse de l'URL..." -ForegroundColor Gray
    
    try {
        $job = Start-Job -ScriptBlock {
            param($url)
            $output = & yt-dlp --dump-json --flat-playlist --socket-timeout 5 $url 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
            return $output
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
                } else {
                    return @{
                        IsPlaylist = $false
                        Count = 1
                        Title = $output.title
                    }
                }
            }
        } else {
            Remove-Job -Job $job -Force
            Write-Host "Timeout lors de l'analyse. Continuation..." -ForegroundColor Yellow
        }
    } catch {
        # Erreur silencieuse
    }
    
    return @{
        IsPlaylist = $false
        Count = 1
        Title = "Video"
    }
}

if (-not (Test-AndInstallDependency)) {
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

    # Etape 1.5 : Verifier si c'est une playlist (avec timeout rapide)
    $playlistInfo = Get-PlaylistInfo -InputUrl $url -TimeoutSeconds 8
    
    if ($playlistInfo.IsPlaylist) {
        Write-Host "`n[ATTENTION] Ceci est une PLAYLIST" -ForegroundColor Yellow
        Write-Host "Titre : $($playlistInfo.Title)" -ForegroundColor Cyan
        Write-Host "Nombre de fichiers : $($playlistInfo.Count)" -ForegroundColor Cyan
        Write-Host ""
        
        $confirmPlaylist = Read-Host "Voulez-vous vraiment telecharger tous les $($playlistInfo.Count) fichiers ? (o/N)"
        
        if ($confirmPlaylist.ToLower() -ne 'o') {
            Write-Host "Telechargement annule." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            continue
        }
    }

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
