# WaddonSync

WaddonSync is a small Windows app that makes it easy to back up and restore your World of Warcraft interface.

What it does now:

- Create local backups of your World of Warcraft folders (WTF and Interface).
- Include/exclude saved variables, keybindings, and Config.wtf when creating backups (Config.wtf included by default).
- Upload backups to Google Drive and manage online backups (list, download, delete).
- Download online backups to your machine and apply them to your WoW folders.
- Apply local backups (with an opt-in toggle to include Config.wtf during restore).
- Manage backups from a single dialog (download/upload/delete, view sizes in MB).
- Show progress and clear status messages for multi-step actions like download → apply.

Platform:

- Windows desktop (built with Flutter). Designed for Windows users who want a simple, reliable way to backup and restore addons and settings.

Future ideas (not implemented yet):

- More cloud providers (OneDrive, Dropbox, Firebase Storage, etc.)
- Scheduled/automatic backups and retention policies
- Per-backup notes

If you need a tool that simply backs up and restores your WoW addons and settings, WaddonSync is built for that. If you want any of the future items above, let me know and we can prioritize them.