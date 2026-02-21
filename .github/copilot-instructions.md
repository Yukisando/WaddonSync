applyTo: '**'
instructions:
  - "This is a Flutter Windows desktop app (WaddonSync) for backing up/restoring World of Warcraft addons and settings, with Google Drive cloud backup support."
  - "Always check `if (!mounted) return;` before using `BuildContext` (e.g. `context`) after any `await` call in StatefulWidget methods. This prevents the `use_build_context_synchronously` lint warning and avoids crashes if the widget is disposed during an async operation."
  - "OAuth credentials (client ID and secret) live in `lib/config/secrets.dart`, which is gitignored. Never hardcode secrets in tracked source files. The template is `lib/config/secrets.example.dart`."
  - "The CI pipeline (`.github/workflows/release.yml`) generates `secrets.dart` at build time from GitHub Secrets (`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`). If adding new secrets, update both the pipeline step and the example file."
  - "The `file_picker` plugin warnings about missing inline implementations are upstream issues — not actionable in this repo. Ignore them."
