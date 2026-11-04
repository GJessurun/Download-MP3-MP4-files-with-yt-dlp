# Téléchargeur yt-dlp pour Windows

Deux scripts en ligne de commande Windows pour télécharger des médias à partir d’URL compatibles avec [yt-dlp](https://github.com/yt-dlp/yt-dlp). Le script principal propose un menu pour choisir l’audio MP3 ou la vidéo MP4, la qualité vidéo et le traitement des playlists. Un second script est dédié aux URL de flux `.m3u8`.

> Utilisez ces scripts uniquement pour des contenus que vous êtes autorisé à télécharger. Respectez les droits d’auteur, les conditions d’utilisation du site source et les règles applicables dans votre pays. Le script M3U8 fournit des en-têtes HTTP et une option d’identification de navigateur ; cela ne garantit pas l’accès et ne doit pas servir à contourner des contrôles d’accès ou des restrictions.

## Scripts

### `yt-dlp_downloader.bat`

Lance un menu interactif qui permet de :

- télécharger l’audio en MP3 ou la vidéo en MP4 ;
- choisir la meilleure qualité vidéo disponible, ou limiter la résolution à 1080p ou 720p ;
- télécharger une vidéo individuelle ou une playlist entière, avec numérotation facultative des pistes ;
- enregistrer les fichiers dans `%USERPROFILE%\Downloads\yt-dlp`.

Le script recherche `yt-dlp.exe` et `ffmpeg.exe` à côté du fichier `.bat`, puis dans le `PATH`. Il vérifie également les mises à jour des dépendances installées avec `winget` et tente de mettre à jour celles signalées comme obsolètes.

### `Downalder .m3u8.bat`

Demande une URL `.m3u8`, puis la transmet à `yt-dlp` avec des en-têtes HTTP dérivés du domaine de l’URL. Le comportement dépend de la source et de ses autorisations ; le script ne peut pas garantir qu’un flux sera disponible ou téléchargeable.

## Prérequis

- Windows avec `cmd.exe` et Windows PowerShell disponibles.
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) installé, accessible dans le `PATH` ou placé à côté du script principal. `winget` est utilisé pour vérifier et mettre à jour les installations gérées par winget, mais n’est pas requis pour utiliser une installation locale ou dans le `PATH`.
- FFmpeg pour l’extraction/conversion MP3. Il est également utilisé pour fusionner les flux audio et vidéo et intégrer les métadonnées et miniatures. Sans FFmpeg, le script principal peut télécharger une vidéo uniquement si une version combinée du flux est disponible.

Installation facultative avec winget :

```powershell
winget install --id yt-dlp.yt-dlp --exact
winget install --id yt-dlp.FFmpeg --exact
```

## Utilisation

1. Téléchargez ou clonez le dépôt.
2. Vérifiez que `yt-dlp.exe` est installé et accessible ; ajoutez aussi `ffmpeg.exe` pour les fonctions qui en dépendent.
3. Double-cliquez sur `yt-dlp_downloader.bat` ou lancez-le depuis une fenêtre de commande.
4. Collez une URL HTTP ou HTTPS, puis suivez les choix affichés.

Pour un flux M3U8 autorisé, lancez `Downalder .m3u8.bat` et collez son URL lorsque le script le demande.

Les fichiers téléchargés par le script principal se trouvent dans :

```text
%USERPROFILE%\Downloads\yt-dlp
```

## Dépannage

- **`yt-dlp est introuvable`** : installez yt-dlp avec winget ou placez `yt-dlp.exe` à côté de `yt-dlp_downloader.bat`.
- **MP3 indisponible** : installez FFmpeg ou placez `ffmpeg.exe` à côté du script, puis relancez-le.
- **Échec d’une URL** : vérifiez que l’adresse est complète et que vous avez le droit d’accéder au contenu. Certains sites ou flux ne sont pas pris en charge par yt-dlp ou peuvent imposer leurs propres restrictions.
- **Mise à jour winget impossible** : le script affiche un avertissement ; vérifiez l’installation et la mise à jour des outils séparément.

## Licence

Aucun fichier de licence n’est fourni dans ce dépôt. Vérifiez les droits applicables avant de réutiliser ou redistribuer les scripts.
