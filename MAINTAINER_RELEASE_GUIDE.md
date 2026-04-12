# Maintainer Release Guide

This document is for maintainers only. User-facing install and usage info belongs in README.md.

## Release Artifacts

The release workflow publishes only these user downloads:

- WaddonSync-Installer-<version>.exe (recommended)
- WaddonSync-Portable-<version>.zip

## Optional Code Signing Secrets

To sign installer and app binaries in CI, set repository secrets:

- CODE_SIGN_CERT_PFX_BASE64
- CODE_SIGN_CERT_PASSWORD
- CODE_SIGN_TIMESTAMP_URL (optional, default: http://timestamp.digicert.com)

If secrets are not set, releases still build and publish unsigned files.

## Google OAuth Build Configuration

Google OAuth values are passed into Flutter builds with `--dart-define`.

For CI releases, set these repository secrets:

- GOOGLE_CLIENT_ID
- GOOGLE_CLIENT_SECRET

The release workflow injects them into `flutter build windows`.

## SHA256 Verification

Generate hashes locally when needed:

```powershell
Get-FileHash .\WaddonSync-Installer-<version>.exe -Algorithm SHA256
Get-FileHash .\WaddonSync-Portable-<version>.zip -Algorithm SHA256
```

## Defender / PUA Notes

When reporting a false positive, collect:

- Category: Incorrectly detected as PUA (potentially unwanted application)
- Detection name: from Windows Security -> Virus & threat protection -> Protection history
- Definition version:

```powershell
Get-MpComputerStatus | Select-Object AntivirusSignatureVersion
```

Additional info should include product name, file name, source URL, and SHA256.

If warnings are from Edge download reputation and no Defender event exists, Protection History may be empty.

## Winget Update Flow

Create a metadata JSON file locally and generate manifests from it:

```json
{
	"PackageIdentifier": "Yukisando.WaddonSync",
	"PackageVersion": "<version>",
	"InstallerType": "inno",
	"InstallerUrl": "https://github.com/Yukisando/WaddonSync/releases/download/v<version>/WaddonSync-Installer-<version>.exe",
	"InstallerSha256": "<sha256>",
	"Scope": "machine"
}
```

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\generate_winget_manifests.ps1 -MetadataPath .\winget-metadata-<version>.json
```

Generated files are placed in:

- tools\winget-manifests\<Publisher>\<Package>\<Version>\

Submit those manifests to microsoft/winget-pkgs in a PR.
