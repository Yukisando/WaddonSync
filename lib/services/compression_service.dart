import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

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

// Prepare temp directory for 7z compression (isolate function)
String prepareTempDirFor7z(Map<String, dynamic> args) {
  final wtfDir = args['wtfDir'] as String;
  final interfaceDir = args['interfaceDir'] as String;
  final includeSavedVars = args['includeSavedVars'] as bool;
  final includeConfig = args['includeConfig'] as bool;
  final includeBindings = args['includeBindings'] as bool;
  final includeInterface = args['includeInterface'] as bool;
  final excludeCaches = args['excludeCaches'] as bool;

  final tempDir = Directory.systemTemp.createTempSync('waddonsync-');

  void copyFileToStore(String storePath, File file) {
    final dest = File(p.join(tempDir.path, storePath));
    dest.parent.createSync(recursive: true);
    file.copySync(dest.path);
  }

  final wtfDirObj = Directory(wtfDir);
  if (wtfDirObj.existsSync()) {
    if (includeSavedVars) {
      for (final entity in wtfDirObj.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: wtfDir);
          final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
          if (parts.contains('savedvariables')) {
            final store = p.join('WTF', p.relative(entity.path, from: wtfDir));
            copyFileToStore(store, entity);
          }
          if (includeBindings) {
            final baseName = p.basename(entity.path).toLowerCase();
            if (baseName.contains('binding') ||
                baseName == 'bindings-cache.wtf') {
              final store = p.join(
                'WTF',
                p.relative(entity.path, from: wtfDir),
              );
              copyFileToStore(store, entity);
            }
          }
        }
      }
    }

    if (includeConfig) {
      final cfg = File(p.join(wtfDir, 'Config.wtf'));
      if (cfg.existsSync()) {
        copyFileToStore(p.join('WTF', 'Config.wtf'), cfg);
      }
    }
  }

  final interfaceDirObj = Directory(interfaceDir);
  if (includeInterface && interfaceDirObj.existsSync()) {
    for (final entity in interfaceDirObj.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: interfaceDir);
        final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
        if (excludeCaches &&
            (parts.contains('cache') || parts.contains('wdb'))) {
          continue;
        }
        final store = p.join(
          'Interface',
          p.relative(entity.path, from: interfaceDir),
        );
        copyFileToStore(store, entity);
      }
    }
  }

  return tempDir.path;
}

// Perform ZIP compression in isolate
List<int> performZip(Map<String, dynamic> args) {
  final wtfDir = args['wtfDir'] as String;
  final interfaceDir = args['interfaceDir'] as String;
  final includeSavedVars = args['includeSavedVars'] as bool;
  final includeConfig = args['includeConfig'] as bool;
  final includeBindings = args['includeBindings'] as bool;
  final includeInterface = args['includeInterface'] as bool;
  final excludeCaches = args['excludeCaches'] as bool;

  final archive = Archive();

  void addFileAt(String storePath, File file) {
    final bytes = file.readAsBytesSync();
    archive.addFile(ArchiveFile(storePath, bytes.length, bytes));
  }

  final wtfDirObj = Directory(wtfDir);
  if (wtfDirObj.existsSync()) {
    if (includeSavedVars) {
      for (final entity in wtfDirObj.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: wtfDir);
          final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
          if (parts.contains('savedvariables')) {
            final store = p.join('WTF', p.relative(entity.path, from: wtfDir));
            addFileAt(store, entity);
          }
          if (includeBindings) {
            final baseName = p.basename(entity.path).toLowerCase();
            if (baseName.contains('binding') ||
                baseName == 'bindings-cache.wtf') {
              final store = p.join(
                'WTF',
                p.relative(entity.path, from: wtfDir),
              );
              addFileAt(store, entity);
            }
          }
        }
      }
    }

    if (includeConfig) {
      final cfg = File(p.join(wtfDir, 'Config.wtf'));
      if (cfg.existsSync()) addFileAt(p.join('WTF', 'Config.wtf'), cfg);
    }
  }

  final interfaceDirObj = Directory(interfaceDir);
  if (includeInterface && interfaceDirObj.existsSync()) {
    for (final entity in interfaceDirObj.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: interfaceDir);
        final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
        if (excludeCaches &&
            (parts.contains('cache') || parts.contains('wdb'))) {
          continue;
        }
        final store = p.join(
          'Interface',
          p.relative(entity.path, from: interfaceDir),
        );
        addFileAt(store, entity);
      }
    }
  }

  final zipEncoder = ZipEncoder();
  final zipData = zipEncoder.encode(archive, level: Deflate.BEST_COMPRESSION)!;
  return zipData;
}
