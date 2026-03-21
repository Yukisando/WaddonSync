# WaddonSync

WaddonSync is a small Windows app that makes it easy to back up and restore your World of Warcraft addons.

What it does:

- Create local backups of your World of Warcraft folders (WTF and Interface).
- Include or exclude SavedVariables, keybindings, and Config.wtf.
- Upload backups to Google Drive and manage online backups (list, download, delete).
- Download online backups to your machine and apply them to your WoW folders.
- Apply local backups with restore filters.
- Manage backups from a single dialog.

Platform:

- Windows desktop (built with Flutter). Designed for Windows users who want a simple, reliable way to backup and restore addons and settings.

Install options:

- Releases provide two options only:
  - `WaddonSync-Installer-<version>.exe` (recommended)
  - `WaddonSync-Portable-<version>.zip`
- Installer EXE uses a standard setup wizard:
  - Lets you choose install folder
  - Registers native uninstall entry in Windows Installed Apps
- Portable ZIP is no-install mode and runs directly after extraction.

Future ideas (not implemented yet):

- More cloud providers (OneDrive, Dropbox, Firebase Storage, etc.)
- Scheduled/automatic backups and retention policies
- Per-backup notes

If you need a tool that simply backs up and restores your WoW addons and settings, WaddonSync is built for that. If you want any of the future items above, let me know and I can prioritize them.
