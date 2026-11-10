import 'dart:io';

import 'package:path/path.dart' as p;

/// One installed game version ("flavor") under the WoW root, e.g. `_retail_`.
///
/// [folder] is also the prefix used inside backup archives. An empty folder
/// means the selected root itself is the install (non-standard layouts and
/// legacy single-version archives, which stored WTF/Interface at the top).
class WowFlavor {
  final String folder;
  final String path;

  const WowFlavor({required this.folder, required this.path});

  String get label => flavorLabel(folder);
  String get wtfPath => p.join(path, 'WTF');
  String get interfacePath => p.join(path, 'Interface');

  Map<String, String> toArgs() => {
    'folder': folder,
    'wtfDir': wtfPath,
    'interfaceDir': interfacePath,
  };
}

const String retailFolder = '_retail_';

const Map<String, String> _knownFlavorLabels = {
  '_retail_': 'Retail',
  '_ptr_': 'Retail PTR',
  '_xptr_': 'Retail Experimental PTR',
  '_beta_': 'Retail Beta',
  '_classic_': 'Classic (progression)',
  '_classic_ptr_': 'Classic PTR',
  '_classic_beta_': 'Classic Beta',
  '_classic_era_': 'Classic Era',
  '_classic_era_ptr_': 'Classic Era PTR',
  '_anniversary_': 'Classic Anniversary',
};

final RegExp _flavorFolderPattern = RegExp(
  r'^_[a-z0-9_]+_$',
  caseSensitive: false,
);

bool isFlavorFolderName(String name) => _flavorFolderPattern.hasMatch(name);

/// Human-readable name. Unknown flavors (new game versions) get a name
/// derived from the folder, e.g. `_forever_` -> `Forever`.
String flavorLabel(String folder) {
  if (folder.isEmpty) return 'Game folder';
  final known = _knownFlavorLabels[folder.toLowerCase()];
  if (known != null) return known;
  return folder
      .split('_')
      .where((s) => s.isNotEmpty)
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join(' ');
}

/// If the user picked a flavor folder (e.g. `.../_retail_`), use its parent
/// so sibling versions are detected too.
String normalizeWowRoot(String selected) {
  final base = p.basename(selected);
  if (isFlavorFolderName(base)) return p.dirname(selected);
  return selected;
}

bool _looksLikeInstall(Directory dir) {
  if (Directory(p.join(dir.path, 'WTF')).existsSync()) return true;
  if (Directory(p.join(dir.path, 'Interface')).existsSync()) return true;
  try {
    return dir
        .listSync(followLinks: false)
        .any((e) => e is File && p.extension(e.path).toLowerCase() == '.exe');
  } catch (_) {
    return false;
  }
}

/// Detects installed versions under [root]. Retail is listed first, the rest
/// alphabetically. Falls back to treating [root] itself as the install when
/// no flavor subfolders exist but WTF/Interface are present directly.
List<WowFlavor> detectWowFlavors(String root) {
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) return const [];

  final flavors = <WowFlavor>[];
  try {
    for (final entity in rootDir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (!isFlavorFolderName(name)) continue;
      if (!_looksLikeInstall(entity)) continue;
      flavors.add(WowFlavor(folder: name, path: entity.path));
    }
  } catch (_) {
    // unreadable root: treat as nothing detected
  }

  flavors.sort((a, b) {
    if (a.folder == retailFolder) return -1;
    if (b.folder == retailFolder) return 1;
    return a.folder.compareTo(b.folder);
  });

  if (flavors.isEmpty &&
      (Directory(p.join(root, 'WTF')).existsSync() ||
          Directory(p.join(root, 'Interface')).existsSync())) {
    flavors.add(WowFlavor(folder: '', path: root));
  }
  return flavors;
}

/// Finds which flavors an extracted backup contains. Returns a map of
/// flavor folder -> extracted directory. Legacy archives (WTF/Interface at the
/// top level) are returned under the empty key.
Map<String, Directory> detectArchiveFlavors(String extractRoot) {
  final result = <String, Directory>{};
  final root = Directory(extractRoot);
  if (!root.existsSync()) return result;

  bool hasContent(String dir) =>
      Directory(p.join(dir, 'WTF')).existsSync() ||
      Directory(p.join(dir, 'Interface')).existsSync();

  for (final entity in root.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = p.basename(entity.path);
    if (isFlavorFolderName(name) && hasContent(entity.path)) {
      result[name] = entity;
    }
  }
  if (hasContent(extractRoot)) result[''] = root;
  return result;
}
