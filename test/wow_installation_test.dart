import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waddonsync/services/compression_service.dart';
import 'package:waddonsync/services/wow_installation.dart';

void _touch(String path) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('x');
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('waddonsync_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('detects every flavor folder, retail first, ignores non-installs', () {
    _touch(p.join(root.path, '_classic_era_', 'WTF', 'Config.wtf'));
    _touch(p.join(root.path, '_retail_', 'Interface', 'AddOns', 'A', 'a.toc'));
    _touch(p.join(root.path, '_forever_', 'Wow.exe'));
    Directory(p.join(root.path, '_empty_')).createSync();
    Directory(p.join(root.path, 'Data')).createSync();

    final flavors = detectWowFlavors(root.path);
    expect(flavors.map((f) => f.folder), [
      '_retail_',
      '_classic_era_',
      '_forever_',
    ]);
    expect(flavors.last.label, 'Forever');
  });

  test('falls back to the root itself for single-install layouts', () {
    _touch(p.join(root.path, 'WTF', 'Config.wtf'));
    final flavors = detectWowFlavors(root.path);
    expect(flavors.single.folder, '');
  });

  test('normalizes a selected flavor folder to the WoW root', () {
    expect(normalizeWowRoot(p.join(root.path, '_retail_')), root.path);
    expect(normalizeWowRoot(root.path), root.path);
  });

  test('backup entries are prefixed per flavor and honor filters', () {
    final retail = p.join(root.path, '_retail_');
    final era = p.join(root.path, '_classic_era_');
    _touch(p.join(retail, 'WTF', 'Account', 'X', 'SavedVariables', 'A.lua'));
    _touch(p.join(retail, 'WTF', 'Account', 'X', 'bindings-cache.wtf'));
    _touch(p.join(retail, 'Interface', 'AddOns', 'A', 'a.toc'));
    _touch(p.join(era, 'WTF', 'Config.wtf'));
    _touch(p.join(era, 'Interface', 'AddOns', 'B', 'b.toc'));
    _touch(p.join(era, 'Interface', 'Icons', 'i.blp'));

    final entries = collectBackupEntries({
      'flavors': detectWowFlavors(root.path).map((f) => f.toArgs()).toList(),
      'includeSavedVars': false,
      'includeConfig': true,
      'includeBindings': true,
      'includeInterface': true,
      'interfaceAddonsOnly': true,
      'excludeCaches': true,
    });

    expect(entries.keys.toSet(), {
      p.join('_retail_', 'WTF', 'Account', 'X', 'bindings-cache.wtf'),
      p.join('_retail_', 'Interface', 'AddOns', 'A', 'a.toc'),
      p.join('_classic_era_', 'WTF', 'Config.wtf'),
      p.join('_classic_era_', 'Interface', 'AddOns', 'B', 'b.toc'),
    });
  });

  test('archive flavor detection recognizes legacy top-level layout', () {
    _touch(p.join(root.path, 'WTF', 'Config.wtf'));
    _touch(p.join(root.path, '_classic_', 'Interface', 'AddOns', 'a.toc'));
    _touch(p.join(root.path, backupMetaFileName));

    final found = detectArchiveFlavors(root.path);
    expect(found.keys.toSet(), {'', '_classic_'});
  });
}
