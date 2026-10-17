# Steam Library Manager

A Windows PowerShell tool for keeping multiple folders for a Steam game and choosing which folder Steam launches. It supports several games and Steam libraries. It does not rename version folders during activation.

## Requirements

- Windows with Windows PowerShell 5.1 and .NET Windows Forms.
- A local Steam installation with libraries registered in `steamapps/libraryfolders.vdf`.
- Each game must already be installed and have one valid `appmanifest_<appid>.acf` in a registered library.
- Enough free disk space for clones. A clone is a full file copy, not a symbolic link.

## Install and run

1. Download the latest `SteamLibraryManager` ZIP from [Releases](https://github.com/mPhpMaster/steam-library-manager/releases) and extract all files into one folder.
2. Run `SteamLibraryManager.bat`. Keep the BAT file and every `SteamLibraryManager*.ps1` file from the ZIP together.
   If upgrading from Steam Game Cloner, copy your existing `SteamGameCloner.json` into that folder before starting the new app. On first launch, the app validates and copies it to `SteamLibraryManager.json`; the old file remains untouched. If both files already exist, the new file takes precedence. Keep your own backup before moving folders. The backup file `SteamGameCloner.json.bak` may also be copied for recovery, but the app does not load it automatically.
3. Click **Add Game**. The list shows games from all registered Steam libraries, including games already added to this tool. Use the Library filter to select **All libraries** or an exact library path; different libraries on the same drive remain separate. Search by name or App ID, then select an available game. Already-added games, missing install folders, and duplicate manifests are shown but cannot be added. Click a column heading to sort ascending; click it again to reverse the order. App IDs sort numerically.
4. Select a version and click **Clone**. The dialog lists registered Steam libraries with full paths and available space. Choose a destination library and optionally enter one version/folder name. Leaving it blank creates a unique copy folder and a display name such as `Copy of Original`. Copying runs in a background process with progress and cancellation. The app rejects conflicting folder names and checks destination free space before copying. Cancelled and failed copies remove their partial files and do not register a version.
5. Double-click a version card (including its text) to activate it directly, or select it once and click **Activate**. If Steam is running, confirm that it should close. The tool offers to launch the game after switching.

The main window has a game sidebar and large version cards. Single-click a version card to reveal **Activate**; double-click it to activate that version. The active version is green. The **Activity** panel records actions and errors. **Close Steam**, **Start Steam**, **Refresh**, and **PLAY** are grouped below the cards. The window starts at 1120 × 720 and can be resized down to 900 × 600.
If a saved numeric game label disagrees with its App ID, or the active manifest does not match a saved version, the app marks the entry for review and blocks Clone, Activate, and Play. It does not change Steam files to repair the entry. Check the App ID and `installdir` in Steam's manifest and the saved folder, back up `SteamLibraryManager.json`, then use **Rename** to correct a misleading label. If the folder or manifest association is wrong, stop and restore the correct saved data from a known good backup rather than editing Steam's library automatically.
The **Name A-Z / Name Z-A** control above the managed games list changes its sort direction while keeping the same game selected.
The **About** button shows the app version, copyright holder, GitHub repository, and releases page.
Game artwork is read from Steam's local cache by App ID when available. An initial-based icon is shown otherwise. Image paths are rediscovered each run and are not stored in `SteamLibraryManager.json`.

**Rename game** and **Rename version** change labels only. **Remove game** and **Remove entry** remove records from the tool only; they never delete game files or Steam manifests. **Play** launches the currently active game through its `steam://rungameid/<appid>` URL.

## How switching works

The tool writes `SteamLibraryManager.json` beside the scripts. It backs up the source manifest as `appmanifest_<appid>.acf.switcher-backup`, changes its `installdir` field, and, when switching libraries, moves the active manifest to the target library's `steamapps` folder. It refuses to switch if duplicate active manifests exist for the same App ID. Steam must be closed before activation.
The project source and latest release are at [mPhpMaster/steam-library-manager](https://github.com/mPhpMaster/steam-library-manager). The app version is defined in `SteamLibraryManager.Version.ps1`.

The cross-library file operations were tested with temporary fake Steam libraries, including switching back. **Actual Steam behavior across two libraries has not been verified.** Steam updates, game file verification, and games with launchers or external dependencies may affect a selected version. Back up modified builds before using the tool.

## Test

From a source checkout (the release ZIP contains only runtime files), run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SteamLibraryManager.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-CloneWorker.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-CardInteraction.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Test-About.ps1
```

The test creates and removes temporary fake Steam libraries; it does not launch Steam or modify your installed games.
The clone worker publishes separate, bounded status snapshots so the UI can read progress without locking the worker's next update. Saved data and manifest replacements retry brief file locks and report a clear error if the lock persists.
