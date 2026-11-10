import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

bool isHiddenOrDotDir(String path) {
  final parts = p.split(path);
  return parts.any((part) => part.startsWith('.'));
}

class CompressionService {
  final Function(String) log;

  CompressionService(this.log);

  // Find 7-Zip executable on Windows
  Future<String?> find7zipExecutable() async {
    try {
      final where = await Process.run('where', ['7z']);
      if (where.exitCode == 0) {
        final path = where.stdout
            .toString()
            .trim()
            .split(RegExp(r'[\r\n]'))
            .first;
        if (path.isNotEmpty) return path;
      }
    } catch (e) {
      // ignore
    }

    final candidates = [
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
    ];

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }

    return null;
  }

  // Create 7z archive directly from source files
  Future<File?> create7zArchive({
    required String timestamp,
    required String exe7z,
    required String tempDirPath,
    required String outputPath,
  }) async {
    try {
      await log('Creating 7z archive with maximum compression...');

      final proc = await Process.run(exe7z, [
        'a',
        '-t7z',
        '-mx=9',
        '-m0=lzma2',
        '-mfb=64',
        '-md=32m',
        '-ms=on',
        outputPath,
        '.',
      ], workingDirectory: tempDirPath);

      // Clean up temp folder
      try {
        final td = Directory(tempDirPath);
        if (await td.exists()) await td.delete(recursive: true);
      } catch (e) {
        await log('Failed to cleanup temp dir: $e');
      }

      if (proc.exitCode == 0) {
        final outFile = File(outputPath);
        if (await outFile.exists()) {
          final size = await outFile.length();
          await log(
            '7z archive created: $outputPath (${(size / (1024 * 1024)).toStringAsFixed(2)} MB)',
          );
          return outFile;
        }
      } else {
        await log(
          '7-Zip failed (exit code ${proc.exitCode}): ${proc.stdout}\n${proc.stderr}',
        );
      }
    } catch (e, st) {
      await log('7-Zip exception: $e\n$st');
    }
    return null;
  }
}

const String backupMetaFileName = 'waddonsync_backup_meta.json';

/// Collects (archive path -> source file) pairs for every selected flavor.
///
/// Expected args: `flavors` (list of `WowFlavor.toArgs()` maps), the include
/// flags, and `excludeCaches`. Each flavor's files are stored under its folder
/// name (e.g. `_retail_/WTF/...`); an empty folder stores them at the top level.
Map<String, String> collectBackupEntries(Map<String, dynamic> args) {
  final flavors = (args['flavors'] as List).cast<Map>();
  final includeSavedVars = args['includeSavedVars'] as bool;
  final includeConfig = args['includeConfig'] as bool;
  final includeBindings = args['includeBindings'] as bool;
  final includeInterface = args['includeInterface'] as bool;
  final interfaceAddonsOnly = (args['interfaceAddonsOnly'] as bool?) ?? false;
  final excludeCaches = args['excludeCaches'] as bool;

  final entries = <String, String>{};

  for (final flavor in flavors) {
    final folder = flavor['folder'] as String;
    final wtfDir = flavor['wtfDir'] as String;
    final interfaceDir = flavor['interfaceDir'] as String;

    final wtfDirObj = Directory(wtfDir);
    if (wtfDirObj.existsSync()) {
      if (includeSavedVars || includeBindings) {
        for (final entity in wtfDirObj.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final rel = p.relative(entity.path, from: wtfDir);
          if (isHiddenOrDotDir(rel)) continue;
          final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
          final baseName = p.basename(entity.path).toLowerCase();
          final isSavedVar = parts.contains('savedvariables');
          final isBinding =
              baseName.contains('binding') || baseName == 'bindings-cache.wtf';
          if ((includeSavedVars && isSavedVar) ||
              (includeBindings && isBinding)) {
            entries[p.join(folder, 'WTF', rel)] = entity.path;
          }
        }
      }

      if (includeConfig) {
        final cfg = File(p.join(wtfDir, 'Config.wtf'));
        if (cfg.existsSync()) {
          entries[p.join(folder, 'WTF', 'Config.wtf')] = cfg.path;
        }
      }
    }

    final interfaceDirObj = Directory(interfaceDir);
    if (includeInterface && interfaceDirObj.existsSync()) {
      for (final entity in interfaceDirObj.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: interfaceDir);
        if (isHiddenOrDotDir(rel)) continue;
        final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
        if (interfaceAddonsOnly && (parts.isEmpty || parts.first != 'addons')) {
          continue;
        }
        if (excludeCaches &&
            (parts.contains('cache') || parts.contains('wdb'))) {
          continue;
        }
        entries[p.join(folder, 'Interface', rel)] = entity.path;
      }
    }
  }

  return entries;
}

// Prepare temp directory for 7z compression (isolate function).
// Same args as collectBackupEntries plus `meta` (JSON string).
String prepareTempDirFor7z(Map<String, dynamic> args) {
  final tempDir = Directory.systemTemp.createTempSync('waddonsync-');

  collectBackupEntries(args).forEach((storePath, sourcePath) {
    final dest = File(p.join(tempDir.path, storePath));
    dest.parent.createSync(recursive: true);
    File(sourcePath).copySync(dest.path);
  });

  File(
    p.join(tempDir.path, backupMetaFileName),
  ).writeAsStringSync(args['meta'] as String);

  return tempDir.path;
}

// Perform ZIP compression in isolate.
// Same args as collectBackupEntries plus `meta` (JSON string).
List<int> performZip(Map<String, dynamic> args) {
  final archive = Archive();

  final metaBytes = utf8.encode(args['meta'] as String);
  archive.addFile(ArchiveFile(backupMetaFileName, metaBytes.length, metaBytes));

  collectBackupEntries(args).forEach((storePath, sourcePath) {
    final bytes = File(sourcePath).readAsBytesSync();
    archive.addFile(ArchiveFile(storePath, bytes.length, bytes));
  });

  final zipEncoder = ZipEncoder();
  final zipData = zipEncoder.encode(archive, level: Deflate.BEST_COMPRESSION)!;
  return zipData;
}
