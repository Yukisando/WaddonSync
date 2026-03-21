import 'dart:convert';

import 'package:http/http.dart' as http;

class AppReleaseInfo {
  final String tagName;
  final String name;
  final String htmlUrl;
  final String body;
  final DateTime? publishedAt;
  final List<AppReleaseAsset> assets;

  const AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    required this.body,
    required this.publishedAt,
    required this.assets,
  });
}

class AppReleaseAsset {
  final String name;
  final String downloadUrl;
  final String contentType;
  final int size;

  const AppReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.contentType,
    required this.size,
  });
}

class AppUpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? message;
  final AppReleaseInfo? release;

  const AppUpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.message,
    this.release,
  });
}

class AppUpdateService {
  // Keep repo explicit so update checks always target production releases.
  static const String _owner = 'Yukisando';
  static const String _repo = 'WaddonSync';

  Future<AppUpdateCheckResult> checkForUpdates({
    required String currentVersion,
    required String currentBuild,
    String? installedReleaseTag,
  }) async {
    final latest = await _fetchLatestRelease();
    if (latest == null) {
      return AppUpdateCheckResult(
        hasUpdate: false,
        currentVersion: _displayVersion(currentVersion, currentBuild),
        latestVersion: 'unknown',
        message: 'Could not fetch latest release from GitHub.',
      );
    }

    if (installedReleaseTag != null &&
        installedReleaseTag.isNotEmpty &&
        installedReleaseTag == latest.tagName) {
      return AppUpdateCheckResult(
        hasUpdate: false,
        currentVersion: _displayVersion(currentVersion, currentBuild),
        latestVersion: latest.tagName,
        release: latest,
      );
    }

    final currentSemver = _parseSemver(currentVersion);
    final latestSemver = _parseSemver(latest.tagName);
    if (currentSemver == null || latestSemver == null) {
      return AppUpdateCheckResult(
        hasUpdate: false,
        currentVersion: _displayVersion(currentVersion, currentBuild),
        latestVersion: latest.tagName,
        message: 'Could not compare versions automatically.',
        release: latest,
      );
    }

    final currentBuildNumber = int.tryParse(currentBuild) ?? 0;
    final latestBuildNumber = _parseBuildNumber(latest.tagName) ?? 0;

    final compare = _compareSemver(currentSemver, latestSemver);
    final hasUpdate =
        compare < 0 || (compare == 0 && latestBuildNumber > currentBuildNumber);

    return AppUpdateCheckResult(
      hasUpdate: hasUpdate,
      currentVersion: _displayVersion(currentVersion, currentBuild),
      latestVersion: latest.tagName,
      release: latest,
    );
  }

  Future<AppReleaseInfo?> _fetchLatestRelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$_owner/$_repo/releases/latest',
    );

    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final assetsRaw = (body['assets'] as List<dynamic>? ?? const []);
    final assets = assetsRaw
        .whereType<Map<String, dynamic>>()
        .map(
          (asset) => AppReleaseAsset(
            name: (asset['name'] as String?) ?? '',
            downloadUrl: (asset['browser_download_url'] as String?) ?? '',
            contentType: (asset['content_type'] as String?) ?? '',
            size: (asset['size'] as int?) ?? 0,
          ),
        )
        .toList();

    return AppReleaseInfo(
      tagName: (body['tag_name'] as String?) ?? '',
      name: (body['name'] as String?) ?? '',
      htmlUrl: (body['html_url'] as String?) ?? '',
      body: (body['body'] as String?) ?? '',
      publishedAt: DateTime.tryParse((body['published_at'] as String?) ?? ''),
      assets: assets,
    );
  }

  AppReleaseAsset? getPreferredWindowsZipAsset(AppReleaseInfo release) {
    final zipAssets = release.assets.where((asset) {
      final name = asset.name.toLowerCase();
      final type = asset.contentType.toLowerCase();
      final isZipType = type.contains('zip') || type.contains('octet-stream');
      return name.endsWith('.zip') && isZipType;
    }).toList();

    if (zipAssets.isEmpty) return null;

    // Prefer assets that look like the packaged Windows desktop release.
    zipAssets.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();
      final aScore =
          (aName.contains('windows') ? 1 : 0) +
          (aName.contains('waddonsync') ? 1 : 0);
      final bScore =
          (bName.contains('windows') ? 1 : 0) +
          (bName.contains('waddonsync') ? 1 : 0);
      return bScore.compareTo(aScore);
    });

    return zipAssets.first;
  }

  AppReleaseAsset? getPreferredWindowsInstallerExeAsset(
    AppReleaseInfo release,
  ) {
    final installerAssets = release.assets.where((asset) {
      final name = asset.name.toLowerCase();
      final type = asset.contentType.toLowerCase();
      final looksExecutable =
          type.contains('octet-stream') || type.contains('x-msdownload');
      return name.endsWith('.exe') && looksExecutable;
    }).toList();

    if (installerAssets.isEmpty) return null;

    installerAssets.sort((a, b) {
      int score(String n) {
        var s = 0;
        if (n.contains('installer')) s += 4;
        if (n.contains('setup')) s += 3;
        if (n.contains('waddonsync')) s += 1;
        return s;
      }

      return score(b.name.toLowerCase()).compareTo(score(a.name.toLowerCase()));
    });

    return installerAssets.first;
  }

  String _displayVersion(String version, String build) {
    if (build.isEmpty) return version;
    return '$version+$build';
  }

  List<int>? _parseSemver(String input) {
    final m = RegExp(r'v?(\d+)\.(\d+)\.(\d+)').firstMatch(input);
    if (m == null) return null;
    return [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    ];
  }

  int _compareSemver(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }

  int? _parseBuildNumber(String input) {
    final m = RegExp(r'build\.(\d+)', caseSensitive: false).firstMatch(input);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }
}
