applyTo: '**'
instructions:
  - "This is a Flutter Windows desktop app (WaddonSync) for backing up/restoring World of Warcraft addons and settings, with Google Drive cloud backup support."
  - "Always check `if (!mounted) return;` before using `BuildContext` (e.g. `context`) after any `await` call in StatefulWidget methods. This prevents the `use_build_context_synchronously` lint warning and avoids crashes if the widget is disposed during an async operation."
  - "OAuth credentials are injected with Flutter `--dart-define` values (`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`). Never hardcode secrets in tracked source files. For local development, use a gitignored `dart_defines.json` file based on `dart_defines.example.json`."
  - "The CI pipeline (`.github/workflows/release.yml`) passes Google OAuth values into `flutter build windows` from GitHub Secrets (`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`). If adding new injected values, update both the workflow and the example file."
  - "The `file_picker` plugin warnings about missing inline implementations are upstream issues — not actionable in this repo. Ignore them."
