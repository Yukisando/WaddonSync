# WaddonSync

WaddonSync is a small Windows app that makes it easy to back up and restore your World of Warcraft addons.

What it does now:

- Create local backups of your World of Warcraft folders (WTF and Interface).
- Include/exclude saved variables, keybindings, and Config.wtf when creating backups (Config.wtf included by default).
- Upload backups to Google Drive and manage online backups (list, download, delete).
- Download online backups to your machine and apply them to your WoW folders.
- Apply local backups (with an opt-in toggle to include Config.wtf during restore).
- Manage backups from a single dialog (download/upload/delete, view sizes in MB).

Platform:

- Windows desktop (built with Flutter). Designed for Windows users who want a simple, reliable way to backup and restore addons and settings.

Windows install and uninstall:

- Releases provide two options only:
	- `WaddonSync-Installer-<version>.exe` (recommended)
	- `WaddonSync-Portable-<version>.zip`
- Installer EXE uses a standard setup wizard:
	- lets users choose install folder
	- registers native uninstall entry in Windows Installed Apps
- Portable ZIP is no-install mode and runs directly after extraction.

Build installer locally (Windows):

1. Run `flutter pub get`
2. Run `flutter build windows --release`
3. Install Inno Setup 6
4. Run `"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\WaddonSync.iss`

SmartScreen and code signing (recommended):

- Unsigned installers often trigger stronger SmartScreen warnings.
- To improve trust and reduce warnings, configure Authenticode signing in CI.
- The release workflow supports optional signing when these repository secrets are set:
	- `CODE_SIGN_CERT_PFX_BASE64`: Base64 of your code-signing `.pfx`
	- `CODE_SIGN_CERT_PASSWORD`: Password for that `.pfx`
	- `CODE_SIGN_TIMESTAMP_URL` (optional): RFC3161 timestamp URL; default is `http://timestamp.digicert.com`

Notes:

- If signing secrets are not configured, releases still build and publish (unsigned).
- For best SmartScreen reputation, use a trusted commercial code-signing certificate (OV or EV).

Future ideas (not implemented yet):

- More cloud providers (OneDrive, Dropbox, Firebase Storage, etc.)
- Scheduled/automatic backups and retention policies
- Per-backup notes

If you need a tool that simply backs up and restores your WoW addons and settings, WaddonSync is built for that. If you want any of the future items above, let me know and I can prioritize them.
