<# :
@echo off
setlocal
chcp 65001 >nul
title Telechargeur yt-dlp
set "YTDLP_SCRIPT=%~f0"

powershell.exe -NoLogo -NoProfile -Command "$script = Get-Content -LiteralPath $env:YTDLP_SCRIPT -Raw; Invoke-Expression $script"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Le programme s'est termine avec une erreur (code %EXIT_CODE%).
pause
exit /b %EXIT_CODE%
#>

[CmdletBinding()]
param ()

$scriptExitCode = 0

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    Write-Warning "L'encodage UTF-8 de la console n'a pas pu etre active."
}

function Read-MenuChoice {
    param (
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string[]]$Choices
    )

    do {
        $choice = (Read-Host $Prompt).Trim()
        if ($Choices -contains $choice) {
            return $choice
        }
        Write-Host "Choix invalide. Valeurs possibles : $($Choices -join ', ')." -ForegroundColor Yellow
    } while ($true)
}

function Test-HttpUrl {
    param ([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $parsedUrl = $null
    return [System.Uri]::TryCreate($Value.Trim(), [System.UriKind]::Absolute, [ref]$parsedUrl) -and
        $parsedUrl.IsWellFormedOriginalString() -and
        ($parsedUrl.Scheme -eq [System.Uri]::UriSchemeHttp -or
         $parsedUrl.Scheme -eq [System.Uri]::UriSchemeHttps) -and
        -not [string]::IsNullOrWhiteSpace($parsedUrl.Host)
}

function Resolve-Executable {
    param (
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptDirectory
    )

    $localExecutable = Join-Path $ScriptDirectory ($Name + ".exe")
    if (Test-Path -LiteralPath $localExecutable -PathType Leaf) {
        return (Resolve-Path -LiteralPath $localExecutable).Path
    }

    $command = Get-Command -Name ($Name + ".exe"), $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    return $null
}

function Quote-ProcessArgument {
    param ([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
        } elseif ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
        } else {
            if ($backslashes -gt 0) {
                [void]$builder.Append(('\' * $backslashes))
                $backslashes = 0
            }
            [void]$builder.Append($character)
        }
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertFrom-PlaylistSummaryOutput {
    param ([Parameter(Mandatory = $true)][string]$Output)

    $lines = $Output.Trim() -split "\r?\n"
    $summaryLine = $lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1
    if ($summaryLine -notmatch "(?s)^(.*)`t(NA|\d+)`t(NA|\d+)$") {
        return [pscustomobject]@{ Status = "unknown"; Reason = "format de reponse yt-dlp inattendu"; Title = $null; Count = $null }
    }

    $title = $matches[1]
    $countValue = $matches[2]
    $indexValue = $matches[3]
    if ($title -eq "NA" -and $countValue -eq "NA" -and $indexValue -eq "NA") {
        return [pscustomobject]@{ Status = "single"; Reason = ""; Title = $null; Count = $null }
    }

    $count = $null
    if ($countValue -ne "NA") {
        $count = [int]$countValue
    }
    return [pscustomobject]@{
        Status = "playlist"
        Reason = ""
        Title = $title
        Count = $count
    }
}

function Get-PlaylistSummary {
    param (
        [Parameter(Mandatory = $true)][string]$YtDlpPath,
        [Parameter(Mandatory = $true)][string]$Url
    )

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $YtDlpPath
    $quotedUrl = Quote-ProcessArgument -Value $Url
    $printTemplate = "%(playlist_title)s`t%(playlist_count)s`t%(playlist_index)s"
    $quotedTemplate = Quote-ProcessArgument -Value $printTemplate
    $process.StartInfo.Arguments = "--flat-playlist --playlist-items 1 --print $quotedTemplate --no-warnings --no-progress --socket-timeout 10 $quotedUrl"
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ Status = "unknown"; Reason = "yt-dlp n'a pas pu demarrer l'analyse de playlist"; Title = $null; Count = $null }
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) {
            $process.Kill()
            $process.WaitForExit()
            return [pscustomobject]@{ Status = "unknown"; Reason = "analyse interrompue apres 20 secondes"; Title = $null; Count = $null }
        }

        $summaryOutput = $stdoutTask.Result
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($summaryOutput)) {
            $reason = $stderrTask.Result.Trim()
            if ([string]::IsNullOrWhiteSpace($reason)) {
                $reason = "yt-dlp n'a pas pu lire les informations du lien"
            }
            return [pscustomobject]@{ Status = "unknown"; Reason = $reason; Title = $null; Count = $null }
        }

        return ConvertFrom-PlaylistSummaryOutput -Output $summaryOutput
    } catch {
        return [pscustomobject]@{ Status = "unknown"; Reason = $_.Exception.Message; Title = $null; Count = $null }
    } finally {
        $process.Dispose()
    }
}

function Start-WingetUpdateCheck {
    param ([Parameter(Mandatory = $true)][string]$PackageId)

    $winget = Get-Command -Name "winget.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $winget) {
        return [pscustomobject]@{ Status = "unknown"; Reason = "winget est introuvable"; Process = $null }
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $winget.Source
    $process.StartInfo.Arguments = "list --id $PackageId --exact --accept-source-agreements --disable-interactivity"
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    try {
        if (-not $process.Start()) {
            $process.Dispose()
            return [pscustomobject]@{ Status = "unknown"; Reason = "winget n'a pas pu demarrer"; Process = $null }
        }

        return [pscustomobject]@{
            Status = "running"
            Reason = ""
            PackageId = $PackageId
            Process = $process
            StartedAt = [DateTime]::UtcNow
            StdoutTask = $process.StandardOutput.ReadToEndAsync()
            StderrTask = $process.StandardError.ReadToEndAsync()
        }
    } catch {
        $process.Dispose()
        return [pscustomobject]@{ Status = "unknown"; Reason = $_.Exception.Message; Process = $null }
    }
}

function ConvertFrom-WingetListOutput {
    param (
        [Parameter(Mandatory = $true)][string]$Output,
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    $normalizedOutput = $Output.Normalize([System.Text.NormalizationForm]::FormD) -replace "\p{Mn}", ""
    $normalizedOutput = $normalizedOutput -replace "[\u2018\u2019]", "'"
    if ($normalizedOutput -match "(?i)(failed .*update.*source|echec de la tentative de mise a jour de la source)") {
        return [pscustomobject]@{ Status = "unknown"; Reason = "la source winget est inaccessible" }
    }
    if ($normalizedOutput -match "(?i)(no installed package found|no package found matching|aucun package installe ne correspond|aucun package ne correspond)") {
        return [pscustomobject]@{ Status = "unknown"; Reason = "paquet non gere par winget" }
    }

    $lines = $normalizedOutput -split "\r?\n"
    $header = $lines | Where-Object { $_ -match "(?i)^\s*(name|nom)\s+id\s+version\s+.*(available|disponible)\s+source\s*$" } | Select-Object -First 1
    $packagePattern = "(?i)(?<!\S)" + [regex]::Escape($PackageId) + "(?!\S)"
    $packageLine = $lines | Where-Object { $_ -match $packagePattern } | Select-Object -First 1
    if ($header -and $packageLine) {
        $availableColumn = [regex]::Match($header, "(?i)\b(available|disponible)\b")
        $sourceColumn = [regex]::Match($header, "(?i)\bsource\s*$")
        if ($availableColumn.Success -and $sourceColumn.Success -and $sourceColumn.Index -gt $availableColumn.Index) {
            $availableLength = $sourceColumn.Index - $availableColumn.Index
            $availableValue = ""
            if ($packageLine.Length -gt $availableColumn.Index) {
                $availableLength = [Math]::Min($availableLength, $packageLine.Length - $availableColumn.Index)
                $availableValue = $packageLine.Substring($availableColumn.Index, $availableLength).Trim()
            }
            if ($availableValue -and $availableValue -notmatch "(?i)^(?:-|N/A|NA)$") {
                return [pscustomobject]@{ Status = "outdated"; Reason = "" }
            }
            return [pscustomobject]@{ Status = "current"; Reason = "" }
        }
    }
    if ($packageLine -and $packageLine -match "(?i)(^|\s)(winget|msstore)\s*$") {
        return [pscustomobject]@{ Status = "current"; Reason = "" }
    }

    return [pscustomobject]@{ Status = "unknown"; Reason = "impossible d'identifier le paquet ou son statut dans winget" }
}

function Complete-WingetUpdateCheck {
    param ([Parameter(Mandatory = $true)]$Check)

    if ($Check.Status -ne "running") {
        return $Check
    }

    $process = $Check.Process
    try {
        $elapsed = [int]([DateTime]::UtcNow - $Check.StartedAt).TotalMilliseconds
        $remainingWait = [Math]::Max(0, 7000 - $elapsed)
        if (-not $process.WaitForExit($remainingWait)) {
            $process.Kill()
            $process.WaitForExit()
            return [pscustomobject]@{ Status = "unknown"; Reason = "delai de verification depasse" }
        }

        $output = $Check.StdoutTask.Result + "`n" + $Check.StderrTask.Result
        return ConvertFrom-WingetListOutput -Output $output -PackageId $Check.PackageId
    } catch {
        return [pscustomobject]@{ Status = "unknown"; Reason = $_.Exception.Message }
    } finally {
        $process.Dispose()
    }
}

function Invoke-WingetUpgrade {
    param (
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$PackageId
    )

    $winget = Get-Command -Name "winget.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $winget) {
        return [pscustomobject]@{ Status = "failed"; Reason = "winget est introuvable" }
    }

    Write-Host "`nNous mettons à jour $Name..." -ForegroundColor Cyan
    try {
        & $winget.Source upgrade --id $PackageId --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            Write-Host "$Name a été mis à jour." -ForegroundColor Green
            return [pscustomobject]@{ Status = "updated"; Reason = "" }
        }

        return [pscustomobject]@{ Status = "failed"; Reason = "winget a échoué (code $exitCode)" }
    } catch {
        return [pscustomobject]@{ Status = "failed"; Reason = $_.Exception.Message }
    }
}

$scriptDirectory = Split-Path -Parent $env:YTDLP_SCRIPT
$ytDlpPath = Resolve-Executable -Name "yt-dlp" -ScriptDirectory $scriptDirectory
$ffmpegPath = Resolve-Executable -Name "ffmpeg" -ScriptDirectory $scriptDirectory
if (-not $ytDlpPath) {
    Write-Host "[ERREUR] yt-dlp est introuvable." -ForegroundColor Red
    Write-Host "Installez-le avec winget install --id yt-dlp.yt-dlp --exact ou placez yt-dlp.exe a cote du script." -ForegroundColor Yellow
    exit 1
}

$startupWarnings = @()
$dependencyChecks = @(
    @{ Name = "yt-dlp"; Path = $ytDlpPath; PackageId = "yt-dlp.yt-dlp" },
    @{ Name = "FFmpeg"; Path = $ffmpegPath; PackageId = "yt-dlp.FFmpeg" }
)

foreach ($dependency in $dependencyChecks) {
    if (-not $dependency.Path) {
        $startupWarnings += "$($dependency.Name) est absent : installez-le avec winget install --id $($dependency.PackageId) --exact."
        continue
    }

    $check = Start-WingetUpdateCheck -PackageId $dependency.PackageId
    $updateStatus = Complete-WingetUpdateCheck -Check $check
    if ($updateStatus.Status -eq "outdated") {
        $upgradeStatus = Invoke-WingetUpgrade -Name $dependency.Name -PackageId $dependency.PackageId
        if ($upgradeStatus.Status -eq "failed") {
            $startupWarnings += "Echec de la mise a jour de $($dependency.Name) ($($upgradeStatus.Reason))."
        }
    } elseif ($updateStatus.Status -eq "unknown") {
        $startupWarnings += "Impossible de verifier $($dependency.Name) avec winget ($($updateStatus.Reason))."
    }
}

if ($startupWarnings.Count -gt 0) {
    Write-Host "`n[VERIFICATION DES DEPENDANCES]" -ForegroundColor Yellow
    foreach ($warning in $startupWarnings) {
        Write-Host "- $warning" -ForegroundColor Yellow
    }
}

$downloadDirectory = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) "Downloads\yt-dlp"

try {
    if (-not (Test-Path -LiteralPath $downloadDirectory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($downloadDirectory) | Out-Null
    }
} catch {
    Write-Host "[ERREUR] Impossible de creer le dossier de telechargement : $downloadDirectory" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkRed
    exit 1
}

do {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       TELECHARGEUR YT-DLP EXPRESS      " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    if (-not $ffmpegPath) {
        Write-Host "FFmpeg : absent (conversion MP3 et fusion video indisponibles)" -ForegroundColor Yellow
    }

    do {
        $url = (Read-Host "`nCollez l'URL HTTP/HTTPS").Trim()
        if (-not (Test-HttpUrl -Value $url)) {
            Write-Host "URL invalide. Une adresse HTTP ou HTTPS complete est requise." -ForegroundColor Red
        }
    } while (-not (Test-HttpUrl -Value $url))

    Write-Host "`nTYPE DE TELECHARGEMENT" -ForegroundColor Yellow
    Write-Host "1. Audio (MP3) "
    Write-Host "2. Video (MP4)"
    $formatChoice = Read-MenuChoice -Prompt "Choix (1 ou 2)" -Choices @("1", "2")

    $qualityChoice = "1"
    if ($formatChoice -eq "2") {
        Write-Host "`nQUALITE VIDEO" -ForegroundColor Yellow
        Write-Host "1. Meilleure qualite disponible"
        Write-Host "2. Maximum 1080p"
        Write-Host "3. Maximum 720p"
        $qualityChoice = Read-MenuChoice -Prompt "Choix (1, 2 ou 3)" -Choices @("1", "2", "3")
    } elseif (-not $ffmpegPath) {
        Write-Host "[ERREUR] FFmpeg est requis pour extraire et convertir l'audio en MP3." -ForegroundColor Red
        Write-Host "Ajoutez ffmpeg.exe au dossier du script ou au PATH, puis relancez." -ForegroundColor Yellow
        Write-Host "1. Recommencer"
        Write-Host "2. Quitter"
        $again = Read-MenuChoice -Prompt "Choix (1 ou 2)" -Choices @("1", "2")
        if ($again -eq "2") {
            break
        }
        continue
    }

    Write-Host "`nAnalyse du lien avec yt-dlp..." -ForegroundColor Cyan
    $playlistInfo = Get-PlaylistSummary -YtDlpPath $ytDlpPath -Url $url
    $playlistChoice = "2"
    $numberPlaylistTracks = $false
    if ($playlistInfo.Status -eq "playlist") {
        $playlistTitle = if ([string]::IsNullOrWhiteSpace($playlistInfo.Title)) { "(titre inconnu)" } else { $playlistInfo.Title }
        $playlistCount = if ($null -eq $playlistInfo.Count) { "nombre de pistes inconnu" } else { "$($playlistInfo.Count) piste(s)" }
        Write-Host "`nPlaylist detectee : $playlistTitle" -ForegroundColor Green
        Write-Host "Contenu : $playlistCount" -ForegroundColor Green
        Write-Host "1. Telecharger toute la playlist"
        Write-Host "2. Telecharger uniquement l'element lie"
        $playlistChoice = Read-MenuChoice -Prompt "Choix (1 ou 2)" -Choices @("1", "2")
        if ($playlistChoice -eq "1") {
            Write-Host "1. Oui, numeroter les pistes"
            Write-Host "2. Non, garder les noms sans numero"
            $numberChoice = Read-MenuChoice -Prompt "Choix (1 ou 2)" -Choices @("1", "2")
            $numberPlaylistTracks = $numberChoice -eq "1"
        }
    } elseif ($playlistInfo.Status -eq "single") {
        Write-Host "Trouvée : une video sera telechargee." -ForegroundColor Cyan
    } else {
        Write-Host "[AVERTISSEMENT] Impossible d'analyser la playlist : $($playlistInfo.Reason)" -ForegroundColor Yellow
        Write-Host "1. Telecharger toute la playlist"
        Write-Host "2. Telecharger uniquement l'element lie"
        $playlistChoice = Read-MenuChoice -Prompt "Choix (1 ou 2)" -Choices @("1", "2")
        if ($playlistChoice -eq "1") {
            Write-Host "1. Oui, numeroter les pistes"
            Write-Host "2. Non, garder les noms sans numero"
            $numberChoice = Read-MenuChoice -Prompt "Choix (1 ou 2)" -Choices @("1", "2")
            $numberPlaylistTracks = $numberChoice -eq "1"
        }
    }

    $outputTemplate = "%(title)s [%(id)s].%(ext)s"
    if ($numberPlaylistTracks) {
        $outputTemplate = "%(playlist_index)03d - %(title)s [%(id)s].%(ext)s"
    }
    $arguments = @(
        "--no-mtime",
        "--windows-filenames",
        "-P", $downloadDirectory,
        "-o", $outputTemplate
    )

    if ($playlistChoice -eq "1") {
        $arguments += "--yes-playlist"
    } else {
        $arguments += "--no-playlist"
    }

    if ($ffmpegPath) {
        $arguments += @("--ffmpeg-location", $ffmpegPath, "--add-metadata", "--embed-thumbnail")
    }

    if ($formatChoice -eq "1") {
        $arguments += @("-x", "--audio-format", "mp3", "--audio-quality", "0")
    } elseif ($ffmpegPath) {
        switch ($qualityChoice) {
            "2" { $videoFormat = "bv*[height<=1080]+ba/b[height<=1080]" }
            "3" { $videoFormat = "bv*[height<=720]+ba/b[height<=720]" }
            default { $videoFormat = "bv+ba/b" }
        }
        $arguments += @("-f", $videoFormat, "--merge-output-format", "mp4")
    } else {
        switch ($qualityChoice) {
            "2" { $videoFormat = "best[height<=1080]" }
            "3" { $videoFormat = "best[height<=720]" }
            default { $videoFormat = "best" }
        }
        $arguments += @("-f", $videoFormat)
        Write-Host "Sans FFmpeg, yt-dlp utilisera un flux video/audio combine lorsqu'il existe." -ForegroundColor Yellow
    }

    $arguments += $url

    Write-Host "`nTelechargement en cours..." -ForegroundColor Green
    try {
        & $ytDlpPath @arguments
        if ($null -eq $LASTEXITCODE) {
            $downloadExitCode = 1
        } else {
            $downloadExitCode = $LASTEXITCODE
        }
    } catch {
        Write-Host "[ERREUR] Impossible de lancer yt-dlp : $($_.Exception.Message)" -ForegroundColor Red
        $downloadExitCode = 1
    }

    if ($downloadExitCode -eq 0) {
        Write-Host "`nTelechargement termine avec succes." -ForegroundColor Green
        Write-Host $downloadDirectory -ForegroundColor Cyan
    } else {
        $scriptExitCode = $downloadExitCode
        Write-Host "`n[ERREUR] yt-dlp a echoue (code $downloadExitCode)." -ForegroundColor Red
        Write-Host "Consultez le message ci-dessus pour connaitre la cause precise." -ForegroundColor Yellow
        Write-Host "Les fichiers eventuellement telecharges se trouvent dans :" -ForegroundColor Yellow
        Write-Host $downloadDirectory -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "1. Recommencer"
    Write-Host "2. Quitter"
    $nextAction = Read-MenuChoice -Prompt "Choix (1 ou 2)" -Choices @("1", "2")
} while ($nextAction -eq "1")

exit $scriptExitCode
