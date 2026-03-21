# Maintainer Release Guide

This document is for maintainers. The user-facing product overview stays in README.md.

## Release Artifacts

The release workflow publishes these user downloads:

- WaddonSync-Installer-<version>.exe (recommended)
- WaddonSync-Portable-<version>.zip

It also publishes maintainer assets:

- checksums-<version>.txt
- winget-metadata-<version>.json

## Optional Code Signing Secrets

To sign installer and app binaries in CI, set repository secrets:

- CODE_SIGN_CERT_PFX_BASE64
- CODE_SIGN_CERT_PASSWORD
- CODE_SIGN_TIMESTAMP_URL (optional, default: http://timestamp.digicert.com)

If secrets are not set, releases still build and publish unsigned files.

## SHA256 Verification

Each release contains checksums-<version>.txt.

Verify locally:

```powershell
Get-FileHash .\WaddonSync-Installer-<version>.exe -Algorithm SHA256
Get-FileHash .\WaddonSync-Portable-<version>.zip -Algorithm SHA256
```

Compare with checksums file entries.

## Defender / PUA Submission Notes

When reporting a false positive:

- Category: Incorrectly detected as PUA (potentially unwanted application)
- Detection name: from Windows Security -> Virus & threat protection -> Protection history
- Definition version:

```powershell
Get-MpComputerStatus | Select-Object AntivirusSignatureVersion
```

Additional info should include product name, file name, source URL, and SHA256.

If warnings are from Edge download reputation and no Defender event exists, Protection History may be empty.

## Winget Update Flow

Use the release metadata file winget-metadata-<version>.json and generate manifests:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\generate_winget_manifests.ps1 -MetadataPath .\winget-metadata-<version>.json
```

Generated files are placed in:

- tools\winget-manifests\<Publisher>\<Package>\<Version>\

Submit those manifests to microsoft/winget-pkgs in a PR.
