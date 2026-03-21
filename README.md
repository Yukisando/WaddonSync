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

- For native Windows "Installed apps" integration and uninstall from the standard Windows UI, use the MSIX package.
- MSIX installs appear in Windows app lists and can be removed with normal uninstall actions.
- The app update button now prefers opening App Installer/MSIX assets from GitHub releases.
- Releases now include both a `.msix` package and a `.appinstaller` file.

Build MSIX locally:

1. Run `flutter pub get`
2. Run `dart run msix:create`
3. Install the generated `.msix` from the build output

Build App Installer publish files locally:

1. Run `flutter pub get`
2. Run `dart run msix:publish --publish-folder-path build\\msix_publish`
3. Use the generated `.appinstaller` and `versions\\*.msix` outputs

Future ideas (not implemented yet):

- More cloud providers (OneDrive, Dropbox, Firebase Storage, etc.)
- Scheduled/automatic backups and retention policies
- Per-backup notes

If you need a tool that simply backs up and restores your WoW addons and settings, WaddonSync is built for that. If you want any of the future items above, let me know and I can prioritize them.
