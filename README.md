# WaddonSync

WaddonSync is a Windows desktop app for backing up and restoring World of Warcraft addons and settings.

It is for players who want a simple way to save their addon setup, keep local backups, and optionally store backups in Google Drive.

## What it does

- Back up your WoW WTF and Interface folders.
- Include or exclude SavedVariables, keybindings, and Config.wtf.
- Restore local backups with restore filters.
- Upload backups to Google Drive.
- List, download, and delete cloud backups from the app.
- Keep backup management in one place instead of manually copying folders around.

## Platform

- Windows desktop only.

## Downloads

Each GitHub release contains only two download options:

- `WaddonSync-Installer-<version>.exe` - recommended for most users
- `WaddonSync-Portable-<version>.zip` - no-install version

### Which one should I use?

Use the installer if you want the normal Windows app experience:

- setup wizard
- install folder selection
- uninstall entry in Windows Installed Apps
- easier for most users

Use the portable zip if you want a self-contained copy you can extract and run anywhere you have write access.

## Installation

### Installer

1. Download `WaddonSync-Installer-<version>.exe` from the latest release.
2. Run the installer.
3. Choose your install location.
4. Launch WaddonSync from the Start menu or installed folder.

### Portable

1. Download `WaddonSync-Portable-<version>.zip` from the latest release.
2. Extract the zip to a normal writable folder.
3. Run `waddonsync.exe`.

Do not run the app directly from inside the zip file.

## Safety and trust

Things users should know before using WaddonSync:

- Releases are published on this GitHub repository.
- Each release contains only the installer EXE and the portable ZIP.
- WaddonSync does not require a WaddonSync account, subscription, or paid service.
- Google Drive support is optional.
- If you connect Google Drive, the app only works with the Google account you authorize.

## First-time setup

1. Select your World of Warcraft folder.
2. Choose what you want to include in backups.
3. Create a local backup.
4. If you want cloud backups, connect Google Drive inside the app.

## Google Drive support

Google Drive is optional.

When you connect Google Drive, WaddonSync uses Google OAuth to request access to files created or opened by this app. It does not need broad access to everything in your Drive for normal use.

## Data and privacy

WaddonSync works with files on your machine and can optionally upload backup archives to your own Google Drive account.

Things users should know:

- Local settings and logs are stored on the local machine.
- Google OAuth tokens are stored locally using secure storage.
- Backups uploaded to Google Drive go to the Google account the user authorizes.
- The app does not require a separate WaddonSync account.
- Other users cannot use this repository to access your Google Drive account.

If you share logs when reporting a bug, review them first in case they include file paths or other local machine details.

## Running from source

If you build the app yourself and want Google Drive support enabled, create a local `dart_defines.json` file from `dart_defines.example.json` and run Flutter with `--dart-define-from-file=dart_defines.json`.

If you build without those values, the app still runs, but Google Drive features stay disabled for that build.

## Notes and limitations

- Windows only.
- World of Warcraft folder detection is best-effort. You can always choose the folder manually.
- Unsigned builds may trigger SmartScreen or antivirus reputation warnings more often than signed builds.
- One-click self-update behavior depends on install location and permissions.

## Reporting issues

If something breaks, open an issue with:

- what you were trying to do
- what happened instead
- whether you used installer or portable
- app version
- relevant log lines if available
