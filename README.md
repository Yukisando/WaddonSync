# WaddonSync

WaddonSync helps Windows users create backups of World of Warcraft interface & settings (WTF + Interface) and manage upload/download of those backups.

## Status
- Scaffolded Flutter Windows app
- Basic UI to select WTF and Interface folders and create ZIP backups (saved to system temp folder)
- Dependencies added: `file_picker`, `archive`, `path`, `path_provider`

## How to run
1. Ensure Flutter is installed and Windows desktop support is enabled
2. From project root run `flutter run -d windows`

## Cloud storage research (summary)
- **OneDrive (Microsoft Graph)**
  - Good fit for Windows users; supports OAuth via Microsoft identity and resumable uploads via `createUploadSession`.
  - Can use a per-app folder or user's Drive; well-documented SDKs.
- **Google Drive**
  - REST API has resumable uploads and an `appData` folder for app-specific data (less intrusive permissions).
  - OAuth 2.0 required (Google Sign-in flows available for Flutter).
- **Dropbox**
  - Supports upload sessions for very large files and provides temporary upload links and app-folder scoped permission.
  - OAuth PKCE works well for desktop apps.
- **Firebase Storage (Google Cloud Storage)**
  - Easiest client integration for Flutter with Firebase SDK, supports resumable uploads and Firebase Auth.
  - Requires owning a Firebase project (costs may apply).
- **AWS S3**
  - Powerful with presigned URLs and multipart uploads but typically needs a server-side component to generate presigned URLs.

## Recommendation
- For a Windows-first consumer app: **OneDrive or Dropbox** are good starting points because many Windows users already have OneDrive/Dropbox and both provide resumable large-file uploads and OAuth flows suited for desktop apps.
- Alternative: Use **Firebase Storage** if you prefer to manage user storage and authentication centrally (more control, slightly more setup).

## Next steps (implementation plan)
1. Add provider abstraction and implement OAuth + resumable upload for one provider (recommend OneDrive first).
2. Add UI to sign in, upload created ZIP (with progress), list backups and download/restore.
3. Add settings and safe restore (back up existing folders before overwriting).

## Questions for you
- Which cloud provider do you prefer I implement first? (OneDrive / Google Drive / Dropbox / Firebase / other)

---

If you'd like I can start implementing OneDrive upload (OAuth + upload session + UI), or implement a Firebase-backed approach that stores backups in a project-owned bucket.
