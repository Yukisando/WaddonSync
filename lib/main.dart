import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';

// Services
import 'services/google_drive_service.dart';
import 'services/compression_service.dart';

// Performs the heavy file collection and compression in a separate isolate.
// Arguments (Map): wtfDir, interfaceDir, includeSavedVars, includeConfig,
// includeBindings, includeInterface, excludeCaches
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

  if (includeInterface) {
    final interfaceDirObj = Directory(interfaceDir);
    if (interfaceDirObj.existsSync()) {
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
          final store = p.join('Interface', rel);
          addFileAt(store, entity);
        }
      }
    }
  }

  final zipEncoder = ZipEncoder();
  final zipData = zipEncoder.encode(archive, level: Deflate.BEST_COMPRESSION)!;
  return zipData;
}

// Prepare a temp folder mirroring the archive structure and copy the selected
// files into it. Returns the path to the created temp folder.
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

void main() {
  // Capture Flutter framework errors and run the app in a guarded zone.
  FlutterError.onError = (FlutterErrorDetails details) {
    // Send framework errors to the console in Release as well.
    FlutterError.presentError(details);
  };

  runZonedGuarded(
    () {
      runApp(const MyApp());
    },
    (error, stack) {
      // Print errors to console for diagnostics (visible if a console is attached).
      print('Unhandled Zone error: $error');
      print(stack);
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Start with dark mode as default
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WaddonSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: HomePage(onToggleTheme: _toggleTheme, themeMode: _themeMode),
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const HomePage({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? wowRootPath;
  String? lastZipPath;

  bool isWorking = false;

  // Derived paths. Prefer the _retail_ subfolder when present.
  String? get _effectiveWowRoot {
    if (wowRootPath == null) return null;
    // If user selected the retail folder directly, honor it
    if (p.basename(wowRootPath!) == '_retail_') return wowRootPath;
    // If a _retail_ subfolder exists under the selected root, prefer it
    final retailCandidate = p.join(wowRootPath!, '_retail_');
    if (Directory(retailCandidate).existsSync()) return retailCandidate;
    // Fallback to the root as given
    return wowRootPath;
  }

  String? get wtfPath =>
      _effectiveWowRoot != null ? p.join(_effectiveWowRoot!, 'WTF') : null;
  String? get interfacePath => _effectiveWowRoot != null
      ? p.join(_effectiveWowRoot!, 'Interface')
      : null;

  // Backup options
  bool includeSavedVars = true;
  bool includeConfig = true; // default on (but only applied when user chooses)
  bool includeBindings = true;
  bool includeInterface = false; // default off
  bool excludeCaches = true;

  // Apply options (for restoring backups)
  bool applySavedVars = true;
  bool applyConfig = false; // default off when applying
  bool applyBindings = true;
  bool applyInterface = true;
  bool cleanApply = true; // Clean mode: delete before applying

  // Google Drive service
  GoogleDriveService? _driveService;

  // Live log streaming
  final List<String> _liveLogs = [];
  StreamController<String>? _logController;
  StreamSubscription<String>? _logSubscription;
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Normal initialization sequence: load settings, detect installation, and migrate temp zips.
    _loadSettings();
    _attemptAutoDetect();
    _migrateOldTempZips();

    // Initialize live log stream
    _logController = StreamController<String>.broadcast();
    _logSubscription = _logController!.stream.listen((line) {
      setState(() {
        _liveLogs.add(line);
        if (_liveLogs.length > 400) _liveLogs.removeAt(0);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (_logScrollController.hasClients) {
            _logScrollController.jumpTo(
              _logScrollController.position.maxScrollExtent,
            );
          }
        } catch (_) {}
      });
    });

    // Initialize Google Drive service
    _driveService = GoogleDriveService(_appendLog);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Post-frame callback for any startup UI work.
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _logController?.close();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<File> _getLocalFile(String name) async {
    final dir = await getApplicationSupportDirectory();
    // put our files under a clearer bundle id folder to avoid com.example
    final appFolder = Directory(
      p.join(dir.parent.path, 'com.waddonsync', 'WaddonSync'),
    );
    if (!await appFolder.exists()) await appFolder.create(recursive: true);
    return File(p.join(appFolder.path, name));
  }

  // Very simple Windows auto-detect: check common Program Files locations
  void _attemptAutoDetect() {
    if (wtfPath != null && interfacePath != null) return;
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final pfx86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    final candidates = [pf, pfx86];
    for (final base in candidates) {
      final wowRetail = p.join(base, 'World of Warcraft');
      final wowRetailRetail = p.join(base, 'World of Warcraft', '_retail_');
      if (Directory(wowRetail).existsSync()) {
        // Use the WoW root when found
        setState(() => wowRootPath ??= wowRetail);
      }
      if (Directory(wowRetailRetail).existsSync()) {
        setState(() => wowRootPath ??= wowRetailRetail);
      }
    }
  }

  // Move any existing temp zips into the WaddonSync app folder (best-effort)
  Future<void> _migrateOldTempZips() async {
    try {
      final pattern = RegExp(
        r'^waddonsync_backup_.*\.(zip|7z)\$',
        caseSensitive: false,
      );
      final tempDir = Directory.systemTemp;
      await for (final entity in tempDir.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is File && pattern.hasMatch(p.basename(entity.path))) {
          final dest = await _getLocalFile(p.basename(entity.path));
          if (!await dest.exists()) {
            await entity.copy(dest.path);
            await entity.delete();
            setState(() => lastZipPath ??= dest.path);
          }
        }
      }

      // Ensure lastZipPath points to the most recent zip in the app folder if any
      final appDir = await getApplicationSupportDirectory();
      // support root might be something like ...\Roaming\com.example, put our files under com.waddonsync/WaddonSync
      final folder = Directory(
        p.join(appDir.parent.path, 'com.waddonsync', 'WaddonSync'),
      );
      if (await folder.exists()) {
        final zips = folder.listSync().whereType<File>().where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return ext == '.zip' || ext == '.7z';
        }).toList();
        zips.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
        if (zips.isNotEmpty) setState(() => lastZipPath = zips.first.path);
      }
    } catch (e) {
      // ignore migration failures
    }
  }

  Future<void> _loadSettings() async {
    try {
      final f = await _getLocalFile('settings.json');
      if (!await f.exists()) return;
      final s = await f.readAsString();
      final m = json.decode(s) as Map<String, dynamic>;
      setState(() {
        includeSavedVars = (m['includeSavedVars'] as bool?) ?? includeSavedVars;
        includeConfig = (m['includeConfig'] as bool?) ?? includeConfig;
        includeBindings = (m['includeBindings'] as bool?) ?? includeBindings;
        includeInterface = (m['includeInterface'] as bool?) ?? includeInterface;
        excludeCaches = (m['excludeCaches'] as bool?) ?? excludeCaches;
        wowRootPath = (m['wowRootPath'] as String?) ?? wowRootPath;
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _saveSettings({bool showSnack = true}) async {
    try {
      final f = await _getLocalFile('settings.json');
      final obj = {
        'includeSavedVars': includeSavedVars,
        'includeConfig': includeConfig,
        'includeBindings': includeBindings,
        'includeInterface': includeInterface,
        'excludeCaches': excludeCaches,
        'wowRootPath': wowRootPath,
      };
      await f.writeAsString(json.encode(obj));
      if (!mounted) return;
      if (showSnack) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save settings: $e')));
    }
  }

  // Upload to Google Drive
  Future<Map<String, String?>?> uploadToDrive(File file) async {
    try {
      if (_driveService == null) {
        await _appendLog('Initializing Google Drive service...');
        _driveService = GoogleDriveService(_appendLog);
      }

      // Initialize if not already authenticated
      final isAuth = await _driveService!.isAuthenticated();
      if (!isAuth) {
        await _appendLog('Google Drive authentication required');
        final initialized = await _driveService!.initialize();
        if (!initialized) {
          return {'error': 'Failed to authenticate with Google Drive'};
        }
      } else {
        // Ensure Drive service is initialized
        final initialized = await _driveService!.initialize();
        if (!initialized) {
          return {'error': 'Failed to initialize Google Drive service'};
        }
      }

      // Upload file
      await _appendLog('Uploading to Google Drive...');
      final result = await _driveService!.uploadFile(file);

      return result;
    } catch (e, st) {
      await _appendLog('Google Drive upload error: $e\n$st');
      return {'error': 'Upload failed: $e'};
    }
  }

  // Download from Google Drive
  Future<File?> downloadFromDrive(String fileId, String savePath) async {
    try {
      _driveService ??= GoogleDriveService(_appendLog);

      await _appendLog('Downloading from Google Drive...');
      final file = await _driveService!.downloadFile(fileId, savePath);

      return file;
    } catch (e, st) {
      await _appendLog('Google Drive download error: $e\n$st');
      return null;
    }
  }

  // Logging helpers: append to a local log file and read logs for UI copy/export
  Future<File> _getLogFile() async => await _getLocalFile('app.log');

  Future<void> _appendLog(String message) async {
    try {
      final f = await _getLogFile();
      final ts = DateTime.now().toIso8601String();
      final line = '[$ts] $message\n';
      await f.writeAsString(line, mode: FileMode.append, flush: true);
      // Also print to console for convenience
      // ignore: avoid_print
      print(line);
      // Push to live log stream for UI clients
      try {
        _logController?.add(line);
      } catch (_) {}
    } catch (e) {
      // best-effort logging only
    }
  }

  // Clear the live app log (truncate)
  Future<void> _clearLogs() async {
    try {
      final f = await _getLogFile();
      if (await f.exists()) {
        await f.writeAsString('', flush: true);
      }
    } catch (e) {
      // best effort
    }
  }

  // Try to locate 7-Zip on Windows
  Future<String?> _find7zipExecutable() async {
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

  // Create a 7z archive directly from source files (returns null on failure)
  Future<File?> _create7zArchive(String timestamp, String exe7z) async {
    try {
      await _appendLog('Creating 7z archive with maximum compression...');

      // Prepare a temporary folder with the exact files we want to compress
      final tempDirPath = await compute(prepareTempDirFor7z, {
        'wtfDir': wtfPath ?? '',
        'interfaceDir': interfacePath ?? '',
        'includeSavedVars': includeSavedVars,
        'includeConfig': includeConfig,
        'includeBindings': includeBindings,
        'includeInterface': includeInterface,
        'excludeCaches': excludeCaches,
      });

      if (tempDirPath.isEmpty)
        throw Exception('Failed to prepare temp dir for 7z');

      final outFile = await _getLocalFile('waddonsync_backup_$timestamp.7z');
      final outPath = outFile.path;

      // Use ultra compression settings for maximum file size reduction
      // -t7z: 7z format, -mx=9: ultra compression, -m0=lzma2: best algorithm
      // -mfb=64: fast bytes, -md=32m: dictionary size, -ms=on: solid archive
      final proc = await Process.run(exe7z, [
        'a',
        '-t7z',
        '-mx=9',
        '-m0=lzma2',
        '-mfb=64',
        '-md=32m',
        '-ms=on',
        outPath,
        '.',
      ], workingDirectory: tempDirPath);

      // Clean up the temp folder regardless of success/failure
      try {
        final td = Directory(tempDirPath);
        if (await td.exists()) await td.delete(recursive: true);
      } catch (e) {
        await _appendLog('Failed to cleanup temp dir: $e');
      }

      if (proc.exitCode == 0) {
        if (await outFile.exists()) {
          final sevenzSize = await outFile.length();
          await _appendLog(
            '7z archive created: ${outFile.path} (${(sevenzSize / (1024 * 1024)).toStringAsFixed(2)} MB)',
          );

          // Prune old backup files (both .zip and .7z) to keep at most 2 backups
          try {
            final appDir = outFile.parent;
            final backups = appDir.listSync().whereType<File>().where((f) {
              final ext = p.extension(f.path).toLowerCase();
              return ext == '.zip' || ext == '.7z';
            }).toList();
            backups.sort(
              (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
            );
            if (backups.length > 2) {
              final toDelete = backups.sublist(2);
              for (final f in toDelete) {
                try {
                  await f.delete();
                  await _appendLog('Pruned old backup: ${f.path}');
                } catch (e) {
                  // ignore individual delete failures
                }
              }
            }
          } catch (e) {
            await _appendLog('Failed to prune backups: $e');
          }

          return outFile;
        }
      } else {
        await _appendLog(
          '7-Zip failed (exit code ${proc.exitCode}): ${proc.stdout}\n${proc.stderr}',
        );
      }
    } catch (e, st) {
      await _appendLog('7-Zip exception: $e\n$st');
    }
    return null;
  }

  Future<bool> _checkNetwork({String host = 'www.google.com'}) async {
    try {
      final res = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 5));
      if (res.isNotEmpty) return true;
      return false;
    } catch (e) {
      await _appendLog('Network check failed for $host: $e');
      return false;
    }
  }

  Future<void> pickWowRootFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select World of Warcraft root folder',
    );
    if (result != null) setState(() => wowRootPath = result);
  }

  Future<File> createZip({
    required String wtfDir,
    required String interfaceDir,
    required bool includeSavedVars,
    required bool includeConfig,
    required bool includeBindings,
    required bool includeInterface,
    required bool excludeCaches,
  }) async {
    setState(() => isWorking = true);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupId = const Uuid().v4();

    // Check if 7-Zip is available - if so, create 7z directly without ZIP
    final exe = await _find7zipExecutable();
    if (exe != null) {
      await _appendLog('7-Zip found, creating 7z archive directly...');
      // Write metadata file with backupId
      final tempMetaDir = await Directory.systemTemp.createTemp(
        'waddonsync-meta-',
      );
      final metaFile = File('${tempMetaDir.path}/waddonsync_backup_meta.json');
      await metaFile.writeAsString(
        jsonEncode({'backupId': backupId, 'timestamp': timestamp}),
      );
      // Prepare temp dir for 7z as before
      final tempDirPath = await compute(prepareTempDirFor7z, {
        'wtfDir': wtfPath ?? '',
        'interfaceDir': interfacePath ?? '',
        'includeSavedVars': includeSavedVars,
        'includeConfig': includeConfig,
        'includeBindings': includeBindings,
        'includeInterface': includeInterface,
        'excludeCaches': excludeCaches,
      });
      if (tempDirPath.isEmpty)
        throw Exception('Failed to prepare temp dir for 7z');
      // Copy meta file into temp dir
      await metaFile.copy('$tempDirPath/waddonsync_backup_meta.json');
      final outFile = await _create7zArchive(timestamp, exe);
      await tempMetaDir.delete(recursive: true);
      if (outFile != null) {
        setState(() {
          lastZipPath = outFile.path;
          isWorking = false;
        });
        return outFile;
      }
      await _appendLog('7-Zip creation failed, falling back to ZIP...');
    }

    // Fallback to ZIP creation
    File outFile = await _getLocalFile('waddonsync_backup_$timestamp.zip');

    final archive = Archive();
    // Add backup metadata file to archive
    final metaContent = jsonEncode({
      'backupId': backupId,
      'timestamp': timestamp,
    });
    archive.addFile(
      ArchiveFile(
        'waddonsync_backup_meta.json',
        metaContent.length,
        utf8.encode(metaContent),
      ),
    );

    Future<void> addFileAt(String storePath, File file) async {
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(storePath, bytes.length, bytes));
    }

    final wtfDirObj = Directory(wtfDir);
    if (wtfDirObj.existsSync()) {
      // SavedVariables files: include all files under any SavedVariables folder
      if (includeSavedVars) {
        await for (final entity in wtfDirObj.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            final rel = p.relative(entity.path, from: wtfDir);
            final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
            if (parts.contains('savedvariables')) {
              final store = p.join(
                'WTF',
                p.relative(entity.path, from: wtfDir),
              );
              await addFileAt(store, entity);
            }
            // include bindings files if selected
            if (includeBindings) {
              final baseName = p.basename(entity.path).toLowerCase();
              if (baseName.contains('binding') ||
                  baseName == 'bindings-cache.wtf') {
                final store = p.join(
                  'WTF',
                  p.relative(entity.path, from: wtfDir),
                );
                await addFileAt(store, entity);
              }
            }
          }
        }
      }

      if (includeConfig) {
        final cfg = File(p.join(wtfDir, 'Config.wtf'));
        if (await cfg.exists()) {
          await addFileAt(p.join('WTF', 'Config.wtf'), cfg);
        }
      }
    }

    final interfaceDirObj = Directory(interfaceDir);
    if (includeInterface && interfaceDirObj.existsSync()) {
      await for (final entity in interfaceDirObj.list(
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
          await addFileAt(store, entity);
        }
      }
    }

    // Offload heavy compression to an isolate and write the result here
    final zipBytes = await compute(performZip, {
      'wtfDir': wtfDir,
      'interfaceDir': interfaceDir,
      'includeSavedVars': includeSavedVars,
      'includeConfig': includeConfig,
      'includeBindings': includeBindings,
      'includeInterface': includeInterface,
      'excludeCaches': excludeCaches,
    });

    await outFile.writeAsBytes(zipBytes, flush: true);

    // Prune old backup files (both .zip and .7z) to keep at most 2 backups
    try {
      final appDir = outFile.parent;
      final zips = appDir.listSync().whereType<File>().where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return ext == '.zip' || ext == '.7z';
      }).toList();
      zips.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      if (zips.length > 2) {
        final toDelete = zips.sublist(2);
        for (final f in toDelete) {
          try {
            await f.delete();
            await _appendLog('Pruned old backup: ${f.path}');
          } catch (e) {
            // ignore individual delete failures
          }
        }
      }
    } catch (e) {
      await _appendLog('Failed to prune backups: $e');
    }

    setState(() {
      lastZipPath = outFile.path;
      isWorking = false;
    });

    return outFile;
  }

  Future<void> handleCreateZip() async {
    if (wowRootPath == null) return;
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Creating backup...'),
          duration: Duration(seconds: 30),
        ),
      );
      final zip = await createZip(
        wtfDir: wtfPath!,
        interfaceDir: interfacePath!,
        includeSavedVars: includeSavedVars,
        includeConfig: includeConfig,
        includeBindings: includeBindings,
        includeInterface: includeInterface,
        excludeCaches: excludeCaches,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup created: ${p.basename(zip.path)}')),
      );

      // Ask user if they want to upload
      if (!mounted) return;
      final upload = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload backup?'),
          content: Text(
            'Backup created successfully: ${p.basename(zip.path)}\n\nWould you like to upload it to Google Drive?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Upload'),
            ),
          ],
        ),
      );

      if (upload == true) {
        if (!mounted) return;
        await uploadFileAndRegister(zip);
      }
    } catch (e) {
      await _appendLog('Error while zipping: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error while zipping: $e')));
    }
  }

  Future<void> handleUploadAndRegister() async {
    if (wowRootPath == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // make the user aware we are zipping first
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Zipping...'),
          duration: Duration(seconds: 30),
        ),
      );
      final zip = await createZip(
        wtfDir: wtfPath!,
        interfaceDir: interfacePath!,
        includeSavedVars: includeSavedVars,
        includeConfig: includeConfig,
        includeBindings: includeBindings,
        includeInterface: includeInterface,
        excludeCaches: excludeCaches,
      );
      if (!mounted) return;

      // after creating a zip, upload it (shared logic)
      await uploadFileAndRegister(zip);
    } catch (e) {
      await _appendLog('Error while uploading/registering: $e');
      setState(() => isWorking = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> uploadLatestAndRegister() async {
    final messenger = ScaffoldMessenger.of(context);
    if (lastZipPath == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('No ZIP available. Create a ZIP first.')),
      );
      return;
    }
    final f = File(lastZipPath!);
    if (!await f.exists()) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Latest ZIP is missing. Please create a ZIP.'),
        ),
      );
      return;
    }
    await uploadFileAndRegister(f);
  }

  Future<void> uploadFileAndRegister(File zip) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // start uploading
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Uploading to Google Drive...'),
          duration: Duration(seconds: 120),
        ),
      );
      setState(() => isWorking = true);
      // quick network check to provide clearer feedback before attempting upload
      final netOk = await _checkNetwork(host: 'www.google.com');
      if (!netOk) {
        final err =
            'Network unreachable: could not connect to the internet (check internet connection, firewall, or proxy).';
        await _appendLog('Upload network check failed: $err');
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Network error'),
            content: SelectableText(err),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  uploadFileAndRegister(zip);
                },
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        setState(() => isWorking = false);
        return;
      }

      final uploadResult = await uploadToDrive(zip);
      setState(() => isWorking = false);

      if (uploadResult == null || uploadResult['fileId'] == null) {
        final err = uploadResult?['error'] ?? 'Upload failed (unknown error)';
        await _appendLog('Upload failed for ${zip.path}: $err');
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Upload failed'),
            content: SelectableText(err),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  uploadFileAndRegister(zip);
                },
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: err));
                  if (!mounted) return;
                  Navigator.of(context).pop();
                },
                child: const Text('Copy error'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }

      final fileId = uploadResult['fileId']!;
      final fileName = uploadResult['fileName'] ?? 'backup.zip';

      await _appendLog('Upload successful! File ID: $fileId');

      // Copy file ID to clipboard for convenience
      await Clipboard.setData(ClipboardData(text: fileId));
      if (!mounted) return;
      final msg = 'Upload succeeded! File ID copied to clipboard.';
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(msg)));

      // show dialog with file info
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('File uploaded to Google Drive:'),
              const SizedBox(height: 8),
              const Text(
                'File Name:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(fileName),
              const SizedBox(height: 8),
              const Text(
                'File ID:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(fileId),
              const SizedBox(height: 12),
              const Text(
                'Your backup is stored in the "WaddonSync Backups" folder in Google Drive.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: fileId));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File ID copied to clipboard')),
                );
              },
              child: const Text('Copy File ID'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      await _appendLog('Error while uploading: $e');
      setState(() => isWorking = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showGoogleDriveSettings() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Drive Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your backups are stored in a "WaddonSync Backups" folder in your Google Drive.',
            ),
            const SizedBox(height: 8),
            const Text(
              'The app keeps your 3 most recent backups.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();

              // Log out from Google Drive
              if (_driveService != null) {
                await _driveService!.logout();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logged out from Google Drive')),
                );
              }
            },
            child: const Text('Logout'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();

              // Re-authenticate with Google Drive
              if (_driveService != null) {
                await _driveService!.logout();
              }
              _driveService = GoogleDriveService(_appendLog);
              final success = await _driveService!.initialize();

              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Google Drive authenticated')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to authenticate')),
                );
              }
            },
            child: const Text('Re-authenticate'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // --- Restore helpers ---
  Future<void> _loadLatestAndApply() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Downloading and restoring latest backup...'),
        duration: Duration(seconds: 120),
      ),
    );

    setState(() => isWorking = true);

    try {
      // Quick network check
      final netOk = await _checkNetwork(host: 'www.googleapis.com');
      if (!netOk) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Network error'),
            content: const SelectableText(
              'Network unreachable: could not connect to the internet.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _loadLatestAndApply();
                },
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        setState(() => isWorking = false);
        return;
      }

      if (wowRootPath == null) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Missing folder'),
            content: const Text(
              'Please select your World of Warcraft root folder before restoring.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        setState(() => isWorking = false);
        return;
      }

      _driveService ??= GoogleDriveService(_appendLog);

      final initialized = await _driveService!.initialize();
      if (!initialized) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to initialize Google Drive')),
        );
        setState(() => isWorking = false);
        return;
      }

      final backups = await _driveService!.listBackups();
      if (backups.isEmpty) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No backups found in your Google Drive'),
          ),
        );
        setState(() => isWorking = false);
        return;
      }

      final latest = backups.first;
      final fileId = latest['fileId'] as String?;
      final fileName = latest['name'] as String?;
      if (fileId == null || fileName == null) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not identify latest backup')),
        );
        setState(() => isWorking = false);
        return;
      }

      // Save the downloaded backup in the app folder so users can inspect it later
      final outFile = await _getLocalFile(fileName);
      final file = await downloadFromDrive(fileId, outFile.path);
      if (file == null) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to download latest backup')),
        );
        setState(() => isWorking = false);
        return;
      }

      // Update local index so Show folder works
      setState(() => lastZipPath = file.path);

      // Ask user if they want to apply the downloaded backup now
      if (!mounted) return;
      bool tempApplySavedVars = applySavedVars;
      bool tempApplyConfig = applyConfig;
      bool tempApplyBindings = applyBindings;
      bool tempApplyInterface = applyInterface;
      bool tempCleanApply = cleanApply;

      final apply = await showDialog<bool>(
        context: context,
        builder: (ctx2) {
          return StatefulBuilder(
            builder: (ctx, setState2) => AlertDialog(
              title: const Text('Backup downloaded'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      'Downloaded "${fileName}" to your local backups.\n\nDo you want to apply this backup to your World of Warcraft folders now?',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select what to apply:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CheckboxListTile(
                      title: const Text('SavedVariables'),
                      subtitle: const Text('Addon settings and data'),
                      value: tempApplySavedVars,
                      onChanged: (v) =>
                          setState2(() => tempApplySavedVars = v ?? false),
                    ),
                    CheckboxListTile(
                      title: const Text('Config.wtf'),
                      subtitle: const Text('Game settings'),
                      value: tempApplyConfig,
                      onChanged: (v) =>
                          setState2(() => tempApplyConfig = v ?? false),
                    ),
                    CheckboxListTile(
                      title: const Text('Keybindings'),
                      subtitle: const Text('Key bindings'),
                      value: tempApplyBindings,
                      onChanged: (v) =>
                          setState2(() => tempApplyBindings = v ?? false),
                    ),
                    CheckboxListTile(
                      title: const Text('Interface'),
                      subtitle: const Text('Addon files'),
                      value: tempApplyInterface,
                      onChanged: (v) =>
                          setState2(() => tempApplyInterface = v ?? false),
                    ),
                    const Divider(),
                    CheckboxListTile(
                      title: const Text('Clean apply'),
                      subtitle: const Text(
                        'Delete existing files before applying',
                      ),
                      value: tempCleanApply,
                      onChanged: (v) =>
                          setState2(() => tempCleanApply = v ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      applySavedVars = tempApplySavedVars;
                      applyConfig = tempApplyConfig;
                      applyBindings = tempApplyBindings;
                      applyInterface = tempApplyInterface;
                      cleanApply = tempCleanApply;
                    });
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          );
        },
      );

      if (apply != true) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Downloaded to: ${file.path}')),
        );
        setState(() => isWorking = false);
        return;
      }

      // User chose to apply: extract and copy using helper
      final err = await _applyBackupFile(
        file,
        applySavedVarsFilter: applySavedVars,
        applyConfigFilter: applyConfig,
        applyBindingsFilter: applyBindings,
        applyInterfaceFilter: applyInterface,
        cleanMode: cleanApply,
      );
      if (err != null) {
        messenger.hideCurrentSnackBar();
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to apply backup: $err')),
        );
        setState(() => isWorking = false);
        return;
      }
    } catch (e, st) {
      await _appendLog('Restore error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore error'),
          content: SelectableText(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      setState(() => isWorking = false);
    }
  }

  Future<bool> _extractArchive(File archiveFile, String destPath) async {
    final ext = p.extension(archiveFile.path).toLowerCase();

    if (ext == '.zip') {
      try {
        final bytes = await archiveFile.readAsBytes();
        final arch = ZipDecoder().decodeBytes(bytes);
        for (final file in arch) {
          final outPath = p.join(destPath, file.name);
          if (file.isFile) {
            final outFile = File(outPath);
            outFile.parent.createSync(recursive: true);
            final content = file.content as List<int>;
            await outFile.writeAsBytes(content, flush: true);
          } else {
            Directory(outPath).createSync(recursive: true);
          }
        }
        return true;
      } catch (e, st) {
        await _appendLog('ZIP extraction failed: $e\n$st');
        return false;
      }
    } else if (ext == '.7z') {
      try {
        final cs = CompressionService(_appendLog);
        final exe = await cs.find7zipExecutable();
        if (exe == null) {
          await _appendLog('7z executable not found');
          return false;
        }
        final proc = await Process.run(exe, [
          'x',
          archiveFile.path,
          '-o$destPath',
          '-y',
        ]);
        if (proc.exitCode == 0) return true;
        await _appendLog(
          '7z extraction failed: ${proc.stdout}\n${proc.stderr}',
        );
        return false;
      } catch (e, st) {
        await _appendLog('7z extraction error: $e\n$st');
        return false;
      }
    }

    await _appendLog('Unsupported archive format: $ext');
    return false;
  }

  Future<void> _copyDirectoryContents(Directory src, Directory dest) async {
    if (!await dest.exists()) await dest.create(recursive: true);

    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: src.path);
      final targetPath = p.join(dest.path, rel);

      if (entity is File) {
        final targetFile = File(targetPath);
        if (await targetFile.exists()) await targetFile.delete();
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetFile.path);
      } else if (entity is Directory) {
        final d = Directory(targetPath);
        if (!await d.exists()) await d.create(recursive: true);
      }
    }
  }

  Future<void> _refreshLocalBackups() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final folder = Directory(
        p.join(appDir.parent.path, 'com.waddonsync', 'WaddonSync'),
      );
      if (!await folder.exists()) {
        setState(() => lastZipPath = null);
        return;
      }
      final zips = folder.listSync().whereType<File>().where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return ext == '.zip' || ext == '.7z';
      }).toList();
      zips.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      if (zips.isNotEmpty) {
        setState(() => lastZipPath = zips.first.path);
        await _appendLog(
          'Refreshed local backups - newest: ${zips.first.path}',
        );
      } else {
        setState(() => lastZipPath = null);
      }
    } catch (e, st) {
      await _appendLog('Failed to refresh local backups: $e\n$st');
    }
  }

  // Opens the local backups folder (creates it if necessary). If a latest backup
  // exists it will be selected, otherwise the folder is simply opened.
  Future<void> _openLocalBackupFolder() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final folder = Directory(
        p.join(appDir.parent.path, 'com.waddonsync', 'WaddonSync'),
      );
      if (!await folder.exists()) await folder.create(recursive: true);

      if (lastZipPath != null && File(lastZipPath!).existsSync()) {
        await Process.run('explorer', [
          '/select,',
          p.normalize(File(lastZipPath!).path),
        ]);
      } else {
        await Process.run('explorer', [p.normalize(folder.path)]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open backup folder: $e')),
      );
    }
  }

  // Shows a dialog listing both local and online backups (Google Drive).
  // Latest is selected by default. Allows downloading/applying a selected
  // backup and deleting individual backups via the bin icon.
  Future<void> _showManageBackups() async {
    final messenger = ScaffoldMessenger.of(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Loading backups...'),
          ],
        ),
      ),
    );

    // Gather local backups
    var localBackups = <Map<String, dynamic>>[];
    try {
      final appDir = await getApplicationSupportDirectory();
      final folder = Directory(
        p.join(appDir.parent.path, 'com.waddonsync', 'WaddonSync'),
      );
      if (await folder.exists()) {
        final files = folder.listSync().whereType<File>().where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return ext == '.zip' || ext == '.7z';
        }).toList();
        files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
        for (final f in files) {
          String? backupId;
          try {
            final ext = p.extension(f.path).toLowerCase();
            if (ext == '.zip') {
              final bytes = await f.readAsBytes();
              final arch = ZipDecoder().decodeBytes(bytes);
              ArchiveFile? meta;
              try {
                meta = arch.firstWhere(
                  (file) => file.name == 'waddonsync_backup_meta.json',
                );
              } catch (_) {
                meta = null;
              }
              if (meta != null) {
                final metaJson =
                    jsonDecode(utf8.decode(meta.content))
                        as Map<String, dynamic>;
                backupId = metaJson['backupId'] as String?;
              }
            } else if (ext == '.7z') {
              // 7z: try to extract meta file using 7z command line
              final tempDir = await Directory.systemTemp.createTemp(
                'waddonsync-meta-extract-',
              );
              final cs = CompressionService(_appendLog);
              final exe = await cs.find7zipExecutable();
              if (exe != null) {
                final proc = await Process.run(exe, [
                  'e',
                  f.path,
                  'waddonsync_backup_meta.json',
                  '-o${tempDir.path}',
                  '-y',
                ]);
                final metaFile = File(
                  '${tempDir.path}/waddonsync_backup_meta.json',
                );
                if (await metaFile.exists()) {
                  final metaJson =
                      jsonDecode(await metaFile.readAsString())
                          as Map<String, dynamic>;
                  backupId = metaJson['backupId'] as String?;
                }
                await tempDir.delete(recursive: true);
              }
            }
          } catch (_) {}
          localBackups.add({
            'type': 'local',
            'path': f.path,
            'name': p.basename(f.path),
            'size': f.lengthSync(),
            'modified': f.statSync().modified.toIso8601String(),
            'backupId': backupId,
          });
        }
      }
    } catch (e) {
      await _appendLog('Failed to list local backups: $e');
    }

    // Gather online backups
    var onlineBackups = <Map<String, dynamic>>[];
    _driveService ??= GoogleDriveService(_appendLog);
    final initialized = await _driveService!.initialize();
    if (initialized) {
      try {
        onlineBackups = await _driveService!.listBackups();
        for (final b in onlineBackups) {
          b['type'] = 'online';
        }
      } catch (e) {
        await _appendLog('Failed to list online backups: $e');
      }
    }

    // Close loading dialog
    if (!mounted) return;
    Navigator.of(context).pop();

    // Combined list
    final allBackups = [...localBackups, ...onlineBackups];

    if (allBackups.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No backups found')));
      return;
    }

    String? selectedId;
    if (allBackups.isNotEmpty) {
      final first = allBackups.first;
      selectedId = first['type'] == 'local'
          ? 'local:${first['path']}'
          : 'online:${first['fileId']}';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState2) => AlertDialog(
          title: const Text('Manage Backups'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx2).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Local backups section
                if (localBackups.isNotEmpty) ...[
                  const Text(
                    'Local Backups',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...localBackups.map((b) {
                    final path = b['path'] as String;
                    final name = b['name'] as String;
                    final size = b['size'] as int;
                    final modified = b['modified'] as String;

                    final backupId = b['backupId'] as String?;
                    final id = 'local:$path';

                    return ListTile(
                      leading: Radio<String>(
                        value: id,
                        groupValue: selectedId ?? '',
                        onChanged: (v) => setState2(() => selectedId = v),
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '$modified • ${(size / (1024 * 1024)).toStringAsFixed(2)} MB'
                        '${backupId != null ? '\nID: $backupId' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.upload),
                            tooltip: 'Upload to Google Drive',
                            onPressed: () async {
                              Navigator.of(ctx2).pop();

                              final file = File(path);
                              if (!await file.exists()) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('File not found'),
                                  ),
                                );
                                return;
                              }

                              if (!mounted) return;
                              await uploadFileAndRegister(file);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            tooltip: 'Delete local backup',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: ctx2,
                                builder: (c) => AlertDialog(
                                  title: const Text('Delete backup?'),
                                  content: Text(
                                    'Delete "$name" from your local backups? This cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(c).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(c).pop(true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm != true) return;

                              try {
                                await File(path).delete();
                                setState2(() => localBackups.remove(b));
                                if (selectedId == id) {
                                  final remaining = [
                                    ...localBackups,
                                    ...onlineBackups,
                                  ];
                                  setState2(
                                    () => selectedId = remaining.isEmpty
                                        ? null
                                        : (remaining.first['type'] == 'local'
                                              ? 'local:${remaining.first['path']}'
                                              : 'online:${remaining.first['fileId']}'),
                                  );
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Backup deleted'),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to delete: $e'),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                ],

                // Online backups section
                if (onlineBackups.isNotEmpty) ...[
                  const Text(
                    'Online Backups (Google Drive)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: onlineBackups.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx3, idx) {
                        final b = onlineBackups[idx];
                        final fid = b['fileId'] as String?;
                        final name = b['name'] as String? ?? '';
                        final created = b['createdTime'] as String? ?? '';
                        final sizeBytes =
                            int.tryParse(b['size']?.toString() ?? '0') ?? 0;
                        final sizeMB = (sizeBytes / (1024 * 1024))
                            .toStringAsFixed(2);
                        final id = 'online:$fid';

                        return ListTile(
                          leading: Radio<String>(
                            value: id,
                            groupValue: selectedId ?? '',
                            onChanged: (v) => setState2(() => selectedId = v),
                          ),
                          title: Text(name),
                          subtitle: Text('$created • $sizeMB MB'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.download),
                                tooltip: 'Download to local',
                                onPressed: fid == null
                                    ? null
                                    : () async {
                                        Navigator.of(ctx2).pop();

                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Downloading backup...',
                                            ),
                                            duration: Duration(seconds: 60),
                                          ),
                                        );

                                        setState(() => isWorking = true);

                                        try {
                                          final outFile = await _getLocalFile(
                                            name,
                                          );
                                          final file = await downloadFromDrive(
                                            fid,
                                            outFile.path,
                                          );

                                          messenger.hideCurrentSnackBar();
                                          if (file != null) {
                                            setState(
                                              () => lastZipPath = file.path,
                                            );
                                            if (!mounted) return;
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Downloaded: ${p.basename(file.path)}',
                                                ),
                                              ),
                                            );
                                          } else {
                                            if (!mounted) return;
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Download failed',
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          setState(() => isWorking = false);
                                        }
                                      },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                tooltip: 'Delete online backup',
                                onPressed: fid == null
                                    ? null
                                    : () async {
                                        final confirm = await showDialog<bool>(
                                          context: ctx2,
                                          builder: (c) => AlertDialog(
                                            title: const Text('Delete backup?'),
                                            content: Text(
                                              'Delete "$name" from your Google Drive backups? This cannot be undone.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(c).pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(c).pop(true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm != true) return;

                                        final ok = await _driveService!
                                            .deleteBackup(fid);
                                        if (ok) {
                                          setState2(
                                            () => onlineBackups.removeAt(idx),
                                          );
                                          if (selectedId == id) {
                                            final remaining = [
                                              ...localBackups,
                                              ...onlineBackups,
                                            ];
                                            setState2(
                                              () =>
                                                  selectedId = remaining.isEmpty
                                                  ? null
                                                  : (remaining.first['type'] ==
                                                            'local'
                                                        ? 'local:${remaining.first['path']}'
                                                        : 'online:${remaining.first['fileId']}'),
                                            );
                                          }
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Backup deleted'),
                                            ),
                                          );
                                        } else {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Failed to delete backup',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ] else if (localBackups.isEmpty) ...[
                  const Expanded(
                    child: Center(child: Text('No online backups found')),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx2).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: selectedId == null
                  ? null
                  : () async {
                      // Determine if selected is local or online
                      if (selectedId!.startsWith('local:')) {
                        final path = selectedId!.substring('local:'.length);
                        final file = File(path);
                        if (!await file.exists()) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selected backup no longer exists'),
                            ),
                          );
                          return;
                        }

                        setState(() => lastZipPath = file.path);

                        // Ask to apply
                        if (!mounted) return;
                        bool tempApplySavedVars = applySavedVars;
                        bool tempApplyConfig = applyConfig;
                        bool tempApplyBindings = applyBindings;
                        bool tempApplyInterface = applyInterface;
                        bool tempCleanApply = cleanApply;
                        final apply = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => StatefulBuilder(
                            builder: (ctx3, setState3) => AlertDialog(
                              title: const Text('Apply local backup'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      'Apply "${p.basename(path)}" to your World of Warcraft folders?',
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Select what to apply:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('SavedVariables'),
                                      subtitle: const Text(
                                        'Addon settings and data',
                                      ),
                                      value: tempApplySavedVars,
                                      onChanged: (v) => setState3(
                                        () => tempApplySavedVars = v ?? false,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('Config.wtf'),
                                      subtitle: const Text('Game settings'),
                                      value: tempApplyConfig,
                                      onChanged: (v) => setState3(
                                        () => tempApplyConfig = v ?? false,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('Keybindings'),
                                      subtitle: const Text('Key bindings'),
                                      value: tempApplyBindings,
                                      onChanged: (v) => setState3(
                                        () => tempApplyBindings = v ?? false,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('Interface'),
                                      subtitle: const Text('Addon files'),
                                      value: tempApplyInterface,
                                      onChanged: (v) => setState3(
                                        () => tempApplyInterface = v ?? false,
                                      ),
                                    ),
                                    const Divider(),
                                    CheckboxListTile(
                                      title: const Text('Clean apply'),
                                      subtitle: const Text(
                                        'Delete existing files before applying',
                                      ),
                                      value: tempCleanApply,
                                      onChanged: (v) => setState3(
                                        () => tempCleanApply = v ?? false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      applySavedVars = tempApplySavedVars;
                                      applyConfig = tempApplyConfig;
                                      applyBindings = tempApplyBindings;
                                      applyInterface = tempApplyInterface;
                                      cleanApply = tempCleanApply;
                                    });
                                    Navigator.of(ctx).pop(true);
                                  },
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          ),
                        );

                        Navigator.of(ctx2).pop();

                        if (apply == true) {
                          // Show applying progress
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => const AlertDialog(
                              content: Row(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 20),
                                  Text('Applying backup...'),
                                ],
                              ),
                            ),
                          );

                          final err = await _applyBackupFile(
                            file,
                            applySavedVarsFilter: applySavedVars,
                            applyConfigFilter: applyConfig,
                            applyBindingsFilter: applyBindings,
                            applyInterfaceFilter: applyInterface,
                            cleanMode: cleanApply,
                          );

                          // Close loading
                          if (!mounted) return;
                          Navigator.of(context).pop();

                          if (err == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Apply completed')),
                            );
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Apply failed: $err')),
                            );
                          }
                        }
                      } else if (selectedId!.startsWith('online:')) {
                        // Show loading
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => const AlertDialog(
                            content: Row(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(width: 20),
                                Text('Downloading backup...'),
                              ],
                            ),
                          ),
                        );

                        final fileId = selectedId!.substring('online:'.length);
                        final bIndex = onlineBackups.indexWhere(
                          (e) => e['fileId'] == fileId,
                        );
                        if (bIndex < 0) {
                          Navigator.of(context).pop(); // Close loading
                          return;
                        }
                        final b = onlineBackups[bIndex];
                        final name = b['name'] as String? ?? 'backup.zip';
                        final outFile = await _getLocalFile(name);
                        final file = await downloadFromDrive(
                          fileId,
                          outFile.path,
                        );

                        // Close loading dialog
                        if (!mounted) return;
                        Navigator.of(context).pop();
                        if (file == null) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to download selected backup',
                              ),
                            ),
                          );
                          return;
                        }

                        setState(() => lastZipPath = file.path);

                        // Ask to apply like existing flow
                        if (!mounted) return;
                        bool tempApplySavedVars = applySavedVars;
                        bool tempApplyConfig = applyConfig;
                        bool tempApplyBindings = applyBindings;
                        bool tempApplyInterface = applyInterface;
                        bool tempCleanApply = cleanApply;
                        final apply = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => StatefulBuilder(
                            builder: (ctx3, setState3) => AlertDialog(
                              title: const Text('Backup downloaded'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      'Downloaded "$name" to your local backups.\n\nDo you want to apply this backup to your World of Warcraft folders now?',
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Select what to apply:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('SavedVariables'),
                                      subtitle: const Text(
                                        'Addon settings and data',
                                      ),
                                      value: tempApplySavedVars,
                                      onChanged: (v) => setState3(
                                        () => tempApplySavedVars = v ?? false,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('Config.wtf'),
                                      subtitle: const Text('Game settings'),
                                      value: tempApplyConfig,
                                      onChanged: (v) => setState3(
                                        () => tempApplyConfig = v ?? false,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('Keybindings'),
                                      subtitle: const Text('Key bindings'),
                                      value: tempApplyBindings,
                                      onChanged: (v) => setState3(
                                        () => tempApplyBindings = v ?? false,
                                      ),
                                    ),
                                    CheckboxListTile(
                                      title: const Text('Interface'),
                                      subtitle: const Text('Addon files'),
                                      value: tempApplyInterface,
                                      onChanged: (v) => setState3(
                                        () => tempApplyInterface = v ?? false,
                                      ),
                                    ),
                                    const Divider(),
                                    CheckboxListTile(
                                      title: const Text('Clean apply'),
                                      subtitle: const Text(
                                        'Delete existing files before applying',
                                      ),
                                      value: tempCleanApply,
                                      onChanged: (v) => setState3(
                                        () => tempCleanApply = v ?? false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      applySavedVars = tempApplySavedVars;
                                      applyConfig = tempApplyConfig;
                                      applyBindings = tempApplyBindings;
                                      applyInterface = tempApplyInterface;
                                      cleanApply = tempCleanApply;
                                    });
                                    Navigator.of(ctx).pop(true);
                                  },
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          ),
                        );

                        Navigator.of(ctx2).pop();

                        if (apply == true) {
                          // Show applying progress
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => const AlertDialog(
                              content: Row(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 20),
                                  Text('Applying backup...'),
                                ],
                              ),
                            ),
                          );

                          final err = await _applyBackupFile(
                            file,
                            applySavedVarsFilter: applySavedVars,
                            applyConfigFilter: applyConfig,
                            applyBindingsFilter: applyBindings,
                            applyInterfaceFilter: applyInterface,
                            cleanMode: cleanApply,
                          );

                          // Close loading
                          if (!mounted) return;
                          Navigator.of(context).pop();

                          if (err == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Apply completed')),
                            );
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Apply failed: $err')),
                            );
                          }
                        } else {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Downloaded to: ${file.path}'),
                            ),
                          );
                        }
                      }
                    },
              child: const Text('Apply Selected'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyLatestLocal() async {
    final messenger = ScaffoldMessenger.of(context);

    // Show loading dialog while checking backups
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Finding latest backup...'),
          ],
        ),
      ),
    );

    setState(() => isWorking = true);

    try {
      // Get local backups
      var localBackups = <Map<String, dynamic>>[];
      try {
        final appDir = await getApplicationSupportDirectory();
        final folder = Directory(
          p.join(appDir.parent.path, 'com.waddonsync', 'WaddonSync'),
        );
        if (await folder.exists()) {
          final files = folder.listSync().whereType<File>().where((f) {
            final ext = p.extension(f.path).toLowerCase();
            return ext == '.zip' || ext == '.7z';
          }).toList();
          files.sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
          for (final f in files) {
            localBackups.add({
              'type': 'local',
              'path': f.path,
              'name': p.basename(f.path),
              'modified': f.statSync().modified,
            });
          }
        }
      } catch (e) {
        await _appendLog('Failed to list local backups: $e');
      }

      // Get online backups
      var onlineBackups = <Map<String, dynamic>>[];
      _driveService ??= GoogleDriveService(_appendLog);
      final initialized = await _driveService!.initialize();
      if (initialized) {
        try {
          final backupsList = await _driveService!.listBackups();
          for (final b in backupsList) {
            final createdStr = b['createdTime'] as String?;
            if (createdStr != null) {
              onlineBackups.add({
                'type': 'online',
                'fileId': b['fileId'],
                'name': b['name'],
                'modified': DateTime.parse(createdStr),
              });
            }
          }
        } catch (e) {
          await _appendLog('Failed to list online backups: $e');
        }
      }

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Find the most recent backup
      final allBackups = [...localBackups, ...onlineBackups];
      if (allBackups.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No backups found')),
        );
        setState(() => isWorking = false);
        return;
      }

      allBackups.sort((a, b) {
        final aDate = a['modified'] as DateTime;
        final bDate = b['modified'] as DateTime;
        return bDate.compareTo(aDate);
      });

      final latest = allBackups.first;
      final isLocal = latest['type'] == 'local';
      final name = latest['name'] as String;

      // Ask user to confirm with config toggle
      if (!mounted) return;
      bool tempApplySavedVars = applySavedVars;
      bool tempApplyConfig = applyConfig;
      bool tempApplyBindings = applyBindings;
      bool tempApplyInterface = applyInterface;
      bool tempCleanApply = cleanApply;
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setState2) => AlertDialog(
            title: const Text('Apply latest backup'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latest backup: $name\nSource: ${isLocal ? 'Local' : 'Google Drive'}',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select what to apply:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  CheckboxListTile(
                    title: const Text('SavedVariables'),
                    subtitle: const Text('Addon settings and data'),
                    value: tempApplySavedVars,
                    onChanged: (v) =>
                        setState2(() => tempApplySavedVars = v ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text('Config.wtf'),
                    subtitle: const Text('Game settings'),
                    value: tempApplyConfig,
                    onChanged: (v) =>
                        setState2(() => tempApplyConfig = v ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text('Keybindings'),
                    subtitle: const Text('Key bindings'),
                    value: tempApplyBindings,
                    onChanged: (v) =>
                        setState2(() => tempApplyBindings = v ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text('Interface'),
                    subtitle: const Text('Addon files'),
                    value: tempApplyInterface,
                    onChanged: (v) =>
                        setState2(() => tempApplyInterface = v ?? false),
                  ),
                  const Divider(),
                  CheckboxListTile(
                    title: const Text('Clean apply'),
                    subtitle: const Text(
                      'Delete existing files before applying',
                    ),
                    value: tempCleanApply,
                    onChanged: (v) =>
                        setState2(() => tempCleanApply = v ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    applySavedVars = tempApplySavedVars;
                    applyConfig = tempApplyConfig;
                    applyBindings = tempApplyBindings;
                    applyInterface = tempApplyInterface;
                    cleanApply = tempCleanApply;
                  });
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );

      if (result != true) {
        setState(() => isWorking = false);
        return;
      }

      File? fileToApply;

      if (isLocal) {
        // Use local file directly
        final path = latest['path'] as String;
        fileToApply = File(path);
        if (!await fileToApply.exists()) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Local backup file not found')),
          );
          setState(() => isWorking = false);
          return;
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Applying backup...'),
            duration: Duration(seconds: 60),
          ),
        );
      } else {
        // Download from Google Drive
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Downloading backup... (1/2)'),
            duration: Duration(seconds: 60),
          ),
        );

        final fileId = latest['fileId'] as String;
        final outFile = await _getLocalFile(name);
        fileToApply = await downloadFromDrive(fileId, outFile.path);

        if (fileToApply == null) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            const SnackBar(content: Text('Failed to download backup')),
          );
          setState(() => isWorking = false);
          return;
        }

        setState(() => lastZipPath = fileToApply!.path);

        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Applying backup... (2/2)'),
            duration: Duration(seconds: 60),
          ),
        );
      }

      // Apply the backup
      final err = await _applyBackupFile(
        fileToApply,
        applySavedVarsFilter: applySavedVars,
        applyConfigFilter: applyConfig,
        applyBindingsFilter: applyBindings,
        applyInterfaceFilter: applyInterface,
        cleanMode: cleanApply,
      );
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      if (err == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Apply completed')),
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text('Apply failed: $err')));
      }
    } catch (e, st) {
      await _appendLog('Apply error: $e\n$st');
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Apply error: $e')));
    } finally {
      setState(() => isWorking = false);
    }
  }

  // Returns null on success, otherwise an error message
  Future<String?> _applyBackupFile(
    File archiveFile, {
    bool applySavedVarsFilter = true,
    bool applyConfigFilter = false,
    bool applyBindingsFilter = true,
    bool applyInterfaceFilter = true,
    bool cleanMode = true,
  }) async {
    try {
      final extractDir = await Directory.systemTemp.createTemp(
        'waddonsync_extract_',
      );
      await _appendLog('Extracting backup to ${extractDir.path}');

      final extractedOk = await _extractArchive(archiveFile, extractDir.path);
      if (!extractedOk) {
        await _appendLog('Extraction failed');
        return 'Failed to extract archive (unsupported format or 7z not found).';
      }

      final wtfSource = Directory(p.join(extractDir.path, 'WTF'));
      final ifaceSource = Directory(p.join(extractDir.path, 'Interface'));

      final bool wtfHasFiles =
          wtfSource.existsSync() &&
          wtfSource
              .listSync(recursive: true, followLinks: false)
              .any((e) => e is File);
      final bool ifaceHasFiles =
          ifaceSource.existsSync() &&
          ifaceSource
              .listSync(recursive: true, followLinks: false)
              .any((e) => e is File);

      if (!wtfHasFiles && !ifaceHasFiles) {
        await _appendLog('Backup contains no files to restore');
        return 'Backup contains no files to restore.';
      }

      // Clean mode: delete selected categories before applying
      if (cleanMode) {
        await _appendLog('Clean mode enabled - removing old files...');

        if (wtfHasFiles &&
            (applySavedVarsFilter ||
                applyConfigFilter ||
                applyBindingsFilter)) {
          final wtfDest = Directory(wtfPath!);
          if (wtfDest.existsSync()) {
            await _appendLog('Cleaning WTF directory...');
            try {
              await wtfDest.delete(recursive: true);
              await wtfDest.create(recursive: true);
              await _appendLog('WTF directory cleaned');
            } catch (e, st) {
              await _appendLog('Failed cleaning WTF: $e\n$st');
              return 'Failed to clean WTF directory: $e';
            }
          }
        }

        if (ifaceHasFiles && applyInterfaceFilter) {
          final ifaceDest = Directory(interfacePath!);
          if (ifaceDest.existsSync()) {
            await _appendLog('Cleaning Interface directory...');
            try {
              await ifaceDest.delete(recursive: true);
              await ifaceDest.create(recursive: true);
              await _appendLog('Interface directory cleaned');
            } catch (e, st) {
              await _appendLog('Failed cleaning Interface: $e\n$st');
              return 'Failed to clean Interface directory: $e';
            }
          }
        }
      }

      if (wtfHasFiles) {
        await _appendLog('Applying WTF...');
        try {
          // Filter out files based on user selection
          final filesToApply = <File>[];

          for (final entity in wtfSource.listSync(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is! File) continue;

            final rel = p.relative(entity.path, from: wtfSource.path);
            final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
            final baseName = p.basename(entity.path).toLowerCase();

            bool shouldInclude = false;

            // Config.wtf
            if (baseName == 'config.wtf') {
              shouldInclude = applyConfigFilter;
            }
            // Bindings
            else if (baseName.contains('binding') ||
                baseName == 'bindings-cache.wtf') {
              shouldInclude = applyBindingsFilter;
            }
            // SavedVariables
            else if (parts.contains('savedvariables')) {
              shouldInclude = applySavedVarsFilter;
            }
            // Other WTF files (include if any WTF filter is on)
            else {
              shouldInclude =
                  applySavedVarsFilter ||
                  applyConfigFilter ||
                  applyBindingsFilter;
            }

            if (shouldInclude) {
              filesToApply.add(entity);
            }
          }

          if (filesToApply.isEmpty) {
            await _appendLog('No WTF files selected to apply');
          } else {
            for (final file in filesToApply) {
              final rel = p.relative(file.path, from: wtfSource.path);
              final dest = File(p.join(wtfPath!, rel));
              await dest.parent.create(recursive: true);
              await file.copy(dest.path);
            }
            await _appendLog('Applied ${filesToApply.length} WTF file(s)');
          }
        } catch (e, st) {
          await _appendLog('Failed copying WTF: $e\n$st');
          return 'Failed to copy WTF files: $e';
        }
      }

      if (ifaceHasFiles && applyInterfaceFilter) {
        await _appendLog('Applying Interface...');
        try {
          await _copyDirectoryContents(ifaceSource, Directory(interfacePath!));
        } catch (e, st) {
          await _appendLog('Failed copying Interface: $e\n$st');
          return 'Failed to copy Interface files: $e';
        }
      } else if (ifaceHasFiles && !applyInterfaceFilter) {
        await _appendLog('Skipping Interface (filter disabled)');
      }

      await _appendLog('Apply completed');
      return null;
    } catch (e, st) {
      await _appendLog('Apply backup failed: $e\n$st');
      return 'Unexpected error: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png', width: 28, height: 28),
            const SizedBox(width: 8),
            const Text('WaddonSync'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.themeMode == ThemeMode.dark
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: 'Google Drive Settings',
            icon: const Icon(Icons.cloud),
            onPressed: _showGoogleDriveSettings,
          ),
          IconButton(
            tooltip: 'Live log',
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (ctx) => SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.6,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            const Text(
                              'Live log',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () async {
                                final allLogs = _liveLogs.join();
                                await Clipboard.setData(
                                  ClipboardData(text: allLogs),
                                );
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Logs copied to clipboard'),
                                  ),
                                );
                              },
                              child: const Text('Copy all'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await _clearLogs();
                                setState(() => _liveLogs.clear());
                              },
                              child: const Text('Clear'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 4),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: StreamBuilder<String>(
                            stream: _logController?.stream,
                            initialData: null,
                            builder: (context, snapshot) {
                              return ListView.builder(
                                controller: _logScrollController,
                                itemCount: _liveLogs.length,
                                itemBuilder: (ctx2, idx) => Text(
                                  _liveLogs[idx],
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),

      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'World of Warcraft folder (Windows)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          wowRootPath ?? 'World of Warcraft root not selected',
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: pickWowRootFolder,
                        child: const Text('Select WoW root'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (wowRootPath != null)
                            ? () async {
                                await Process.run('explorer', [
                                  p.normalize(wowRootPath!),
                                ]);
                              }
                            : null,
                        child: const Text('Open WoW folder'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (wowRootPath != null) ...[
                    Row(
                      children: [
                        Expanded(child: Text('WTF: ${wtfPath ?? 'missing'}')),
                        if (wtfPath != null)
                          IconButton(
                            tooltip: 'Open WTF',
                            onPressed: () async {
                              await Process.run('explorer', [
                                p.normalize(wtfPath!),
                              ]);
                            },
                            icon: const Icon(Icons.folder_open),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Interface: ${interfacePath ?? 'missing'}',
                          ),
                        ),
                        if (interfacePath != null)
                          IconButton(
                            tooltip: 'Open Interface',
                            onPressed: () async {
                              await Process.run('explorer', [
                                p.normalize(interfacePath!),
                              ]);
                            },
                            icon: const Icon(Icons.folder_open),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),

                  const Text(
                    'Backup options',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  CheckboxListTile(
                    title: const Text('SavedVariables (recommended)'),
                    value: includeSavedVars,
                    onChanged: (v) =>
                        setState(() => includeSavedVars = v ?? true),
                  ),
                  CheckboxListTile(
                    title: const Text('Config.wtf (engine settings)'),
                    value: includeConfig,
                    onChanged: (v) => setState(() {
                      includeConfig = v ?? false;
                      _saveSettings(showSnack: false);
                    }),
                  ),
                  CheckboxListTile(
                    title: const Text('Keybindings (bindings-cache.wtf)'),
                    value: includeBindings,
                    onChanged: (v) => setState(() {
                      includeBindings = v ?? false;
                      _saveSettings(showSnack: false);
                    }),
                  ),
                  CheckboxListTile(
                    title: const Text('Interface (addons) — optional'),
                    value: includeInterface,
                    onChanged: (v) => setState(() {
                      includeInterface = v ?? false;
                      _saveSettings(showSnack: false);
                    }),
                  ),
                  CheckboxListTile(
                    title: const Text('Exclude Cache/WDB folders'),
                    value: excludeCaches,
                    onChanged: (v) => setState(() {
                      excludeCaches = v ?? true;
                      _saveSettings(showSnack: false);
                    }),
                  ),

                  Row(
                    children: [
                      // Local backup actions
                      ElevatedButton(
                        onPressed: (wowRootPath != null && !isWorking)
                            ? handleCreateZip
                            : null,
                        child: isWorking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create New Backup'),
                      ),
                      const SizedBox(width: 4),
                      // Upload icon button
                      IconButton(
                        icon: const Icon(Icons.upload),
                        tooltip: 'Upload Latest Backup to Google Drive',
                        onPressed: (lastZipPath != null && !isWorking)
                            ? uploadLatestAndRegister
                            : null,
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (!isWorking) ? _applyLatestLocal : null,
                        child: const Text('Apply Latest Backup'),
                      ),

                      const Spacer(),

                      // Utility actions with icons
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Show Folder',
                        onPressed: (!isWorking) ? _openLocalBackupFolder : null,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: _refreshLocalBackups,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.storage),
                        tooltip: 'Manage Backups',
                        onPressed: (!isWorking) ? _showManageBackups : null,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Text(
                    'Backups are automatically stored in your Google Drive',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),

          // Live log panel
        ],
      ),
    );
  }
}
