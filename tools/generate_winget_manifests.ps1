param(
  [Parameter(Mandatory = $true)]
  [string]$MetadataPath,

  [string]$OutputRoot = ".\\tools\\winget-manifests",
  [string]$PackageName = "WaddonSync",
  [string]$Publisher = "Yukisando",
  [string]$PublisherUrl = "https://github.com/Yukisando",
  [string]$PublisherSupportUrl = "https://github.com/Yukisando/WaddonSync/issues",
  [string]$Author = "Yukisando",
  [string]$Moniker = "waddonsync",
  [string]$ShortDescription = "Backup and restore World of Warcraft addons and settings",
  [string]$License = "Proprietary",
  [string]$LicenseUrl = "https://github.com/Yukisando/WaddonSync/blob/main/LICENSE",
  [string]$PackageUrl = "https://github.com/Yukisando/WaddonSync",
  [string]$ReleaseNotesUrl = "https://github.com/Yukisando/WaddonSync/releases",
  [string]$Tags = "wow,world-of-warcraft,addon,backup,flutter"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $MetadataPath)) {
  throw "Metadata JSON not found: $MetadataPath"
}

$meta = Get-Content -Raw -Path $MetadataPath | ConvertFrom-Json
if (-not $meta.PackageIdentifier) { throw "PackageIdentifier is missing in metadata." }
if (-not $meta.PackageVersion) { throw "PackageVersion is missing in metadata." }
if (-not $meta.InstallerUrl) { throw "InstallerUrl is missing in metadata." }
if (-not $meta.InstallerSha256) { throw "InstallerSha256 is missing in metadata." }

$identifier = [string]$meta.PackageIdentifier
$version = [string]$meta.PackageVersion
$installerUrl = [string]$meta.InstallerUrl
$installerSha = [string]$meta.InstallerSha256

$manifestVersion = "1.9.0"
$scope = if ($meta.Scope) { [string]$meta.Scope } else { "machine" }
$installerType = if ($meta.InstallerType) { [string]$meta.InstallerType } else { "inno" }

$parts = $identifier.Split('.')
if ($parts.Length -lt 2) {
  throw "PackageIdentifier should be in Publisher.App format. Got: $identifier"
}

$pathParts = @($OutputRoot) + $parts + @($version)
$outDir = Join-Path -Path $pathParts[0] -ChildPath ($pathParts[1..($pathParts.Length - 1)] -join "\\")
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$tagLines = ""
$tagList = $Tags.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
foreach ($tag in $tagList) {
  $tagLines += "  - $tag`n"
}

$escapedShortDescription = $ShortDescription.Replace("'", "''")

$versionManifest = @"
# Created with tools/generate_winget_manifests.ps1
PackageIdentifier: $identifier
PackageVersion: $version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $manifestVersion
"@

$installerManifest = @"
# Created with tools/generate_winget_manifests.ps1
PackageIdentifier: $identifier
PackageVersion: $version
InstallerType: $installerType
Scope: $scope
Installers:
  - Architecture: x64
    InstallerUrl: $installerUrl
    InstallerSha256: $installerSha
ManifestType: installer
ManifestVersion: $manifestVersion
"@

$defaultLocaleManifest = @"
# Created with tools/generate_winget_manifests.ps1
PackageIdentifier: $identifier
PackageVersion: $version
PackageLocale: en-US
Publisher: $Publisher
PublisherUrl: $PublisherUrl
PublisherSupportUrl: $PublisherSupportUrl
Author: $Author
PackageName: $PackageName
PackageUrl: $PackageUrl
License: $License
LicenseUrl: $LicenseUrl
ShortDescription: '$escapedShortDescription'
Moniker: $Moniker
ReleaseNotesUrl: $ReleaseNotesUrl
Tags:
$tagLines
ManifestType: defaultLocale
ManifestVersion: $manifestVersion
"@

$versionPath = Join-Path $outDir "$identifier.yaml"
$installerPath = Join-Path $outDir "$identifier.installer.yaml"
$defaultLocalePath = Join-Path $outDir "$identifier.locale.en-US.yaml"

Write-Utf8NoBomFile -Path $versionPath -Content $versionManifest
Write-Utf8NoBomFile -Path $installerPath -Content $installerManifest
Write-Utf8NoBomFile -Path $defaultLocalePath -Content $defaultLocaleManifest

Write-Host "Generated winget manifest files:"
Write-Host " - $versionPath"
Write-Host " - $installerPath"
Write-Host " - $defaultLocalePath"
