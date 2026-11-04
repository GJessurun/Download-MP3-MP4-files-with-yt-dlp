@echo off
chcp 65001 > nul
title yt-dlp M3U8 Downloader Pro

echo =======================================================================
echo               YT-DLP M3U8 BYPASS DOWNLOADER
echo =======================================================================
echo.

:: Demande l'URL une seule fois à l'utilisateur
set /p m3u8="[1/1] Colle le lien .m3u8 ici et appuie sur Entrée : "
echo.

:: Extraction 100% automatique du domaine/sous-domaine à partir de l'URL m3u8
for /f "delims=" %%i in ('powershell -Command "[System.Uri]('%m3u8%').Host"') do set "site=%%i"

if "%site%"=="" (
    echo [ERREUR] URL invalide ou impossible à analyser.
    pause
    exit /b
)

echo [INFO] Détection de la source : https://%site%
echo [INFO] Lancement du téléchargement avec TOUS les contournements...
echo.

:: Exécution de yt-dlp avec TOUTES les armes anti-bot combinées
yt-dlp ^
  --add-header "Origin: https://%site%" ^
  --add-header "Referer: https://%site%/" ^
  --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" ^
  --impersonate chrome ^
  --no-live-from-start ^
  --sleep-requests 1.2 ^
  "%m3u8%"

echo.
echo =======================================================================
echo Téléchargement terminé ou interrompu.
echo =======================================================================
pause