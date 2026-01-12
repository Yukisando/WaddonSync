import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

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

  final interfaceDirObj = Directory(interfaceDir);
  if (includeInterface && interfaceDirObj.existsSync()) {
    for (final entity in interfaceDirObj.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: interfaceDir);
        final parts = p.split(rel).map((s) => s.toLowerCase()).toList();
        if (excludeCaches && (parts.contains('cache') || parts.contains('wdb')))
          continue;
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
      if (cfg.existsSync()) copyFileToStore(p.join('WTF', 'Config.wtf'), cfg);
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
        if (excludeCaches && (parts.contains('cache') || parts.contains('wdb')))
          continue;
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WaddonSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? wtfPath;
  String? interfacePath;
  String? lastZipPath;

  bool isWorking = false;

  // sync id and options
  String? syncId;
  bool includeSavedVars = true;
  bool includeConfig = true;
  bool includeBindings = true;
  bool includeInterface = true;
  bool excludeCaches = true;

  // Settings (persisted)
  String? gistIdSetting; // the gist id where the registry.json is stored
  String? githubTokenSetting; // personal access token (optional)
  String?
  filebinBinSetting; // optional explicit bin name for filebin uploads // provider is fixed to filebin.net

  // admin controls
  String? adminHash; // hashed password stored in settings
  bool adminUnlocked = false;

  @override
  void initState() {
    super.initState();
    _loadOrCreateSyncId();
    _attemptAutoDetect();
    _migrateOldTempZips();
    // ensure admin password is present (hardcoded default for now)
    adminHash ??= _hashPassword('lasagne');
    // admin locked by default
    adminUnlocked = false;
  }

  final TextEditingController syncIdController = TextEditingController();
  final TextEditingController adminPasswordController = TextEditingController();
  final TextEditingController newAdminPasswordController =
      TextEditingController();

  @override
  void dispose() {
    syncIdController.dispose();
    adminPasswordController.dispose();
    newAdminPasswordController.dispose();
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

  Future<void> _loadOrCreateSyncId() async {
    try {
      final f = await _getLocalFile('sync_id.txt');
      if (await f.exists()) {
        final s = await f.readAsString();
        setState(() => syncId = s.trim());
      } else {
        final s = _generateSyncId(16);
        await f.writeAsString(s);
        setState(() => syncId = s);
      }
    } catch (e) {
      // ignore and generate in-memory
      setState(() => syncId = _generateSyncId(16));
    }

    // load saved settings (gist id / token)
    await _loadSettings();
    // migrate any old app folder names to com.waddonsync root
    await _migrateAppFolderIfNeeded();
  }

  String _generateSyncId(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Future<void> _saveSyncId(String newId) async {
    final f = await _getLocalFile('sync_id.txt');
    await f.writeAsString(newId);
    setState(() => syncId = newId);
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
        final wtf = p.join(wowRetail, 'WTF');
        final iface = p.join(wowRetail, 'Interface');
        if (Directory(wtf).existsSync()) {
          setState(() => wtfPath ??= wtf);
        }
        if (Directory(iface).existsSync()) {
          setState(() => interfacePath ??= iface);
        }
      }
      if (Directory(wowRetailRetail).existsSync()) {
        final wtf = p.join(wowRetailRetail, 'WTF');
        final iface = p.join(wowRetailRetail, 'Interface');
        if (Directory(wtf).existsSync()) {
          setState(() => wtfPath ??= wtf);
        }
        if (Directory(iface).existsSync()) {
          setState(() => interfacePath ??= iface);
        }
      }
    }
  }

  // Move any existing temp zips into the WaddonSync app folder (best-effort)
  Future<void> _migrateOldTempZips() async {
    try {
      final pattern = RegExp(
        r'^waddonsync_backup_.*\.zip\$',
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
        final zips = folder
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path).toLowerCase() == '.zip')
            .toList();
        zips.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
        if (zips.isNotEmpty) setState(() => lastZipPath = zips.first.path);
      }
    } catch (e) {
      // ignore migration failures
    }
  }

  // Migrate existing app folder (if it was created under com.example) to com.waddonsync/WaddonSync
  Future<void> _migrateAppFolderIfNeeded() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final oldFolder = Directory(p.join(appDir.path, 'WaddonSync'));
      final newFolder = Directory(
        p.join(appDir.parent.path, 'com.waddonsync', 'WaddonSync'),
      );
      if (await oldFolder.exists()) {
        if (!await newFolder.exists()) await newFolder.create(recursive: true);
        for (final entity in oldFolder.listSync(recursive: false)) {
          final dest = p.join(newFolder.path, p.basename(entity.path));
          if (entity is File) {
            final f = File(dest);
            if (!await f.exists()) await entity.copy(dest);
          } else if (entity is Directory) {
            final d = Directory(dest);
            if (!await d.exists()) await entity.rename(dest);
          }
        }
        // attempt to remove old folder if empty
        try {
          if (oldFolder.listSync().isEmpty) {
            await oldFolder.delete(recursive: true);
          }
        } catch (e) {
          await _appendLog('Failed to remove old folder: $e');
        }
        final zips = newFolder
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path).toLowerCase() == '.zip')
            .toList();
        zips.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );
        if (zips.isNotEmpty) setState(() => lastZipPath = zips.first.path);
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _loadSettings() async {
    try {
      final f = await _getLocalFile('settings.json');
      if (!await f.exists()) return;
      final s = await f.readAsString();
      final m = json.decode(s) as Map<String, dynamic>;
      setState(() {
        gistIdSetting = (m['gistId'] as String?)?.trim();
        githubTokenSetting = (m['githubToken'] as String?)?.trim();
        filebinBinSetting = (m['filebinBin'] as String?)?.trim();
        // Only overwrite the admin hash if a non-empty value was saved. This preserves
        // the built-in default (hashed 'lasagne') when settings.json contains an
        // empty string or was not previously set.
        final loadedAdminHash = (m['adminHash'] as String?)?.trim();
        if (loadedAdminHash != null && loadedAdminHash.isNotEmpty) {
          adminHash = loadedAdminHash;
        }
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _saveSettings() async {
    try {
      final f = await _getLocalFile('settings.json');
      final obj = {
        'gistId': gistIdSetting ?? '',
        'githubToken': githubTokenSetting ?? '',
        'filebinBin': filebinBinSetting ?? '',
        'adminHash': adminHash ?? '',
      };
      await f.writeAsString(json.encode(obj));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save settings: $e')));
    }
  }

  Future<String?> createRegistryGist(String token) async {
    try {
      final uri = Uri.parse('https://api.github.com/gists');
      final body = json.encode({
        'description': 'WaddonSync registry',
        'public': false,
        'files': {
          'registry.json': {'content': json.encode({})},
        },
      });
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'token $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data['id'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _setAdminPassword(String password) {
    adminHash = _hashPassword(password);
    _saveSettings();
    setState(() => adminUnlocked = true);
  }

  bool _verifyAdminPassword(String password) {
    if (adminHash == null || adminHash!.isEmpty) return false;
    return _hashPassword(password) == adminHash;
  }

  // Upload to transfer.sh and try to extract any expiry/ttl from response headers
  Future<Map<String, String?>?> uploadToTransferSh(File file) async {
    // transfer.sh support has been removed. Use filebin.net instead.
    await _appendLog(
      'transfer.sh disabled; attempted upload to transfer.sh blocked by policy.',
    );
    return {'error': 'transfer.sh disabled; use filebin.net instead'};
  }

  // Test if we can reach filebin.net with a simple HTTP request
  Future<bool> _testFilebinConnection() async {
    try {
      await _appendLog('Testing connection to filebin.net...');
      final testUri = Uri.parse('https://filebin.net/');
      final response = await http
          .get(testUri)
          .timeout(const Duration(seconds: 10));
      await _appendLog('Connection test: HTTP ${response.statusCode}');
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      await _appendLog('Connection test failed: $e');
      return false;
    }
  }

  // Upload using curl as fallback (more reliable for large files)
  Future<Map<String, String?>?> _uploadViacurl(File file, String bin) async {
    try {
      final name = p.basename(file.path);
      final url = 'https://filebin.net/$bin/';

      await _appendLog('Attempting upload via curl...');

      // Use curl with form upload
      final result = await Process.run('curl', [
        '-X', 'POST',
        '-F', 'file=@${file.path}',
        '--max-time', '600', // 10 minute timeout
        '--connect-timeout', '30',
        '-w', '\\n%{http_code}', // Write HTTP code on new line
        url,
      ], runInShell: true);

      await _appendLog('curl exit code: ${result.exitCode}');
      if (result.stdout.toString().isNotEmpty) {
        await _appendLog('curl output: ${result.stdout}');
      }
      if (result.stderr.toString().isNotEmpty) {
        await _appendLog('curl stderr: ${result.stderr}');
      }

      if (result.exitCode == 0) {
        final uploadUrl = 'https://filebin.net/$bin/$name';
        await _appendLog('curl upload succeeded: $uploadUrl');
        return {'url': uploadUrl, 'bin': bin};
      }

      return {
        'error':
            'curl failed with exit code ${result.exitCode}: ${result.stderr}',
      };
    } catch (e, st) {
      await _appendLog('curl upload failed: $e\\n$st');
      return {'error': 'curl not available or failed: $e'};
    }
  }

  // Upload to filebin.net via multipart POST to https://filebin.net/<bin>/
  Future<Map<String, String?>?> uploadToFilebin(
    File file, {
    String? bin,
  }) async {
    http.Client? client;
    final chosenBin =
        bin ??
        (filebinBinSetting?.isNotEmpty == true
            ? filebinBinSetting!
            : 'wowui-${_generateSyncId(8)}');

    try {
      final name = p.basename(file.path);
      final uri = Uri.parse('https://filebin.net/$chosenBin/');
      final fileSize = await file.length();
      final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
      await _appendLog(
        'Uploading ${file.path} ($sizeMB MB) to filebin $chosenBin',
      );

      // Warn if file is very large
      if (fileSize > 50 * 1024 * 1024) {
        await _appendLog(
          'WARNING: File is >50MB. Upload may be slow or fail. Consider uploading smaller backups.',
        );
      }

      // Test connection first
      final canConnect = await _testFilebinConnection();
      if (!canConnect) {
        await _appendLog('Connection test failed. Trying curl fallback...');
        return await _uploadViacurl(file, chosenBin);
      }

      // Use IOClient for better control
      client = http.Client();
      final req = http.MultipartRequest('POST', uri);

      // Use streaming instead of loading entire file into memory
      final stream = file.openRead();
      final part = http.MultipartFile('file', stream, fileSize, filename: name);
      req.files.add(part);

      // Set headers for better upload reliability
      req.headers['Connection'] = 'keep-alive';

      // Adjust timeout based on file size (20 minutes for large files)
      final timeout = fileSize > 20 * 1024 * 1024
          ? const Duration(minutes: 20)
          : const Duration(minutes: 10);

      await _appendLog(
        'Starting upload (timeout: ${timeout.inMinutes} min)...',
      );
      final streamed = await client
          .send(req)
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException(
                'Upload timed out after ${timeout.inMinutes} minutes. File may be too large.',
              );
            },
          );

      final respBody = await streamed.stream.bytesToString();
      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        final url = 'https://filebin.net/$chosenBin/$name';
        await _appendLog('Filebin upload succeeded: $url');
        return {'url': url, 'bin': chosenBin};
      }
      final err =
          'filebin responded with status ${streamed.statusCode}: $respBody';
      await _appendLog('Filebin upload failed: $err');
      return {'error': err};
    } catch (e, st) {
      final err = 'Exception during filebin upload: $e\n$st';
      await _appendLog(err);

      // Try curl as fallback for connection issues
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Write failed') ||
          e.toString().contains('Connection')) {
        await _appendLog('HTTP client failed. Trying curl fallback...');
        client?.close();
        return await _uploadViacurl(file, chosenBin);
      }

      return {'error': err};
    } finally {
      client?.close();
    }
  }

  Future<bool> updateRegistryOnGithub(
    String id,
    String transferUrl, {
    String? expires,
    String? provider,
    String? extra,
  }) async {
    final gistId = gistIdSetting;
    final token = githubTokenSetting ?? Platform.environment['GITHUB_TOKEN'];
    if (gistId == null || gistId.isEmpty) return false;
    if (token == null || token.isEmpty) return false;

    final gistApi = Uri.parse('https://api.github.com/gists/$gistId');
    try {
      final resp = await http.get(gistApi);
      if (resp.statusCode != 200) return false;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final files = data['files'] as Map<String, dynamic>;
      final registryContent = files['registry.json']?['content'] ?? '{}';
      final registry = json.decode(registryContent) as Map<String, dynamic>;
      final entry = {
        'url': transferUrl,
        'timestamp': DateTime.now().toIso8601String(),
        'expires': expires,
        'provider': provider ?? 'transfer',
      };
      if (extra != null) entry['extra'] = extra;
      registry[id] = entry;

      final patchBody = json.encode({
        'files': {
          'registry.json': {'content': json.encode(registry)},
        },
      });

      final patchResp = await http.patch(
        gistApi,
        headers: {
          'Authorization': 'token $token',
          'Content-Type': 'application/json',
        },
        body: patchBody,
      );
      return patchResp.statusCode >= 200 && patchResp.statusCode < 300;
    } catch (e) {
      return false;
    }
  }

  Future<String?> fetchUrlFromRegistry(String id) async {
    final gistId = gistIdSetting;
    if (gistId == null || gistId.isEmpty) return null;
    final gistApi = Uri.parse('https://api.github.com/gists/$gistId');
    try {
      final resp = await http.get(gistApi);
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final files = data['files'] as Map<String, dynamic>;
      final registryContent = files['registry.json']?['content'] ?? '{}';
      final registry = json.decode(registryContent) as Map<String, dynamic>;
      final entry = registry[id];
      if (entry == null) return null;
      return entry['url'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<File?> downloadUrlToTemp(String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;
      final tmp = File(p.join(Directory.systemTemp.path, p.basename(url)));
      await tmp.writeAsBytes(resp.bodyBytes);
      return tmp;
    } catch (e) {
      await _appendLog('downloadUrlToTemp error: $e');
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
    } catch (e) {
      // best-effort logging only
    }
  }

  Future<String> _readLogs({int maxChars = 64 * 1024}) async {
    try {
      final f = await _getLogFile();
      if (!await f.exists()) return '';
      final s = await f.readAsString();
      if (s.length <= maxChars) return s;
      // return last maxChars characters with an indicator
      return '... (truncated) ...\n${s.substring(s.length - maxChars)}';
    } catch (e) {
      return 'Failed to read log: $e';
    }
  }

  // Write a provided string to an export log file and return the path
  Future<String?> _writeLogsToExportFile(String logs) async {
    try {
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final out = await _getLocalFile('app_export_$ts.log');
      await out.writeAsString(logs, flush: true);
      return out.path;
    } catch (e) {
      await _appendLog('Failed to write export logs: $e');
      return null;
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

      if (tempDirPath.isEmpty) return null;

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

  // Legacy method - kept for compatibility but no longer used
  Future<File> _trySevenZipCompression(File zipFile) async {
    try {
      final exe = await _find7zipExecutable();
      if (exe == null) {
        await _appendLog('7-Zip not found, using standard ZIP compression');
        return zipFile;
      }

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

      if (tempDirPath.isEmpty) return zipFile;

      final outPath = zipFile.path.replaceAll(
        RegExp(r'\.zip\$', caseSensitive: false),
        '.7z',
      );

      // Use ultra compression settings for maximum file size reduction
      // -t7z: 7z format, -mx=9: ultra compression, -m0=lzma2: best algorithm
      // -mfb=64: fast bytes, -md=32m: dictionary size, -ms=on: solid archive
      final proc = await Process.run(exe, [
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
        final outFile = File(outPath);
        if (await outFile.exists()) {
          final zipSize = await zipFile.length();
          final sevenzSize = await outFile.length();
          final savings = ((zipSize - sevenzSize) / zipSize * 100)
              .toStringAsFixed(1);
          try {
            await zipFile.delete();
          } catch (e) {
            await _appendLog('Failed to delete original ZIP: $e');
          }
          await _appendLog(
            '7-Zip created ${outFile.path} (${(sevenzSize / (1024 * 1024)).toStringAsFixed(2)} MB, $savings% smaller than ZIP)',
          );
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
    return zipFile;
  }

  Future<bool> _checkNetwork({String host = 'filebin.net'}) async {
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

  void _showLogsDialog() async {
    // Read full logs (up to 10MB) and then export them to a file so we can
    // safely clear the live app log to avoid old logs accumulating.
    final logs = await _readLogs(maxChars: 10 * 1024 * 1024);
    final exportedPath = await _writeLogsToExportFile(logs);
    // Clear the live log now that we've exported a copy for the user
    await _clearLogs();

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Application logs'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(logs.isNotEmpty ? logs : '(no logs)'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: logs));
              if (!mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () async {
              if (exportedPath != null) {
                await Process.run('explorer', ['/select,', exportedPath]);
              }
            },
            child: const Text('Show file'),
          ),
          TextButton(
            onPressed: () async {
              if (exportedPath == null) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Export failed')));
                return;
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Logs exported to $exportedPath')),
              );
              await Process.run('explorer', ['/select,', exportedPath]);
            },
            child: const Text('Export'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> pickWtfFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select WTF folder',
    );
    if (result != null) setState(() => wtfPath = result);
  }

  Future<void> pickInterfaceFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Interface folder',
    );
    if (result != null) setState(() => interfacePath = result);
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

    // Check if 7-Zip is available - if so, create 7z directly without ZIP
    final exe = await _find7zipExecutable();
    if (exe != null) {
      await _appendLog('7-Zip found, creating 7z archive directly...');
      final outFile = await _create7zArchive(timestamp, exe);
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
    if (wtfPath == null || interfacePath == null) return;
    try {
      final messenger = ScaffoldMessenger.of(context);
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup created: ${zip.path}')));
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
    if (wtfPath == null || interfacePath == null) return;
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
          content: Text('Uploading to filebin.net...'),
          duration: Duration(seconds: 120),
        ),
      );
      setState(() => isWorking = true);
      // quick network check to provide clearer feedback before attempting upload
      final netOk = await _checkNetwork(host: 'filebin.net');
      if (!netOk) {
        final err =
            'Network unreachable: could not resolve filebin.net (check internet connection, firewall, or proxy).';
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
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showLogsDialog();
                },
                child: const Text('View logs'),
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

      final uploadResult = await uploadToFilebin(zip);
      setState(() => isWorking = false);

      if (uploadResult == null || uploadResult['url'] == null) {
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
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showLogsDialog();
                },
                child: const Text('View logs'),
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

      final url = uploadResult['url']!;
      final expires = uploadResult['expires'];

      await _appendLog('Upload result URL: $url (expires: $expires)');

      // attempt to update registry (best-effort)
      final did = await updateRegistryOnGithub(
        syncId ?? '',
        url,
        expires: expires,
        provider: 'filebin',
        extra: (uploadResult['bin'] ?? ''),
      );
      await _appendLog(
        'Registry update for ${syncId ?? ''}: ${did ? 'ok' : 'failed'}',
      );

      // show the result and copy url to clipboard for convenience
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      final msg = did
          ? 'Upload succeeded and registry updated. URL copied to clipboard.'
          : 'Upload succeeded. URL copied to clipboard.';
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(msg)));

      // show dialog with link and copy/open actions + expiry note
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Link:'),
              SelectableText(url),
              const SizedBox(height: 8),
              Text(
                expires != null
                    ? 'Note: link metadata: $expires'
                    : 'Note: filebin links are temporary and may expire',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () async {
                await Process.run('rundll32', [
                  'url.dll,FileProtocolHandler',
                  url,
                ]);
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Open'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      await _appendLog('Error while uploading/registering: $e');
      setState(() => isWorking = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> handleSyncById(String id) async {
    if (id.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Fetching registry...')));
    final url = await fetchUrlFromRegistry(id);
    if (url == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No entry found for that ID.')),
      );
      return;
    }
    final file = await downloadUrlToTemp(url);
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to download file.')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Downloaded to ${file.path}')));
  }

  void _onAdminPressed() {
    // Show a single password dialog and ensure the controller is cleared on cancel/success.
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin unlock'),
        content: TextField(
          controller: adminPasswordController,
          decoration: const InputDecoration(hintText: 'Enter admin password'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              adminPasswordController.clear();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final p = adminPasswordController.text;
              if (_verifyAdminPassword(p)) {
                setState(() => adminUnlocked = true);
                adminPasswordController.clear();
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Admin unlocked')));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid password')),
                );
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
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
            tooltip: 'Logs',
            icon: const Icon(Icons.bug_report),
            onPressed: () => _showLogsDialog(),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select source folders (Windows)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(wtfPath ?? 'WTF folder not selected')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: pickWtfFolder,
                    child: const Text('Select WTF'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      interfacePath ?? 'Interface folder not selected',
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: pickInterfaceFolder,
                    child: const Text('Select Interface'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              const Text(
                'Backup options',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              CheckboxListTile(
                title: const Text('SavedVariables (recommended)'),
                value: includeSavedVars,
                onChanged: (v) => setState(() => includeSavedVars = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('Config.wtf (engine settings)'),
                value: includeConfig,
                onChanged: (v) => setState(() => includeConfig = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('Keybindings (bindings-cache.wtf)'),
                value: includeBindings,
                onChanged: (v) => setState(() => includeBindings = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('Interface (addons) — optional'),
                value: includeInterface,
                onChanged: (v) => setState(() => includeInterface = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('Exclude Cache/WDB folders'),
                value: excludeCaches,
                onChanged: (v) => setState(() => excludeCaches = v ?? true),
              ),

              Row(
                children: [
                  ElevatedButton(
                    onPressed:
                        (wtfPath != null && interfacePath != null && !isWorking)
                        ? handleCreateZip
                        : null,
                    child: isWorking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create ZIP'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: (lastZipPath != null && !isWorking)
                        ? uploadLatestAndRegister
                        : null,
                    child: isWorking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Upload latest'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: (lastZipPath != null)
                        ? () async {
                            // reveal and select the file in explorer
                            final file = File(lastZipPath!);
                            if (file.existsSync()) {
                              await Process.run('explorer', [
                                '/select,',
                                p.normalize(file.path),
                              ]);
                            }
                          }
                        : null,
                    child: const Text('Show folder'),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Text(
                'Sync ID',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(syncId ?? 'Generating...')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (syncId == null) return;
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: syncId!));
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Sync ID copied to clipboard'),
                        ),
                      );
                    },
                    child: const Text('Copy'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final newId = _generateSyncId(16);
                      final messenger = ScaffoldMessenger.of(context);
                      await _saveSyncId(newId);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('New Sync ID generated')),
                      );
                    },
                    child: const Text('Regenerate'),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Text(
                'Sync by ID',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: syncIdController,
                      decoration: const InputDecoration(
                        hintText: 'Enter Sync ID',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () =>
                        handleSyncById(syncIdController.text.trim()),
                    child: const Text('Download'),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Builder(
                builder: (ctx) {
                  if (adminUnlocked) {
                    return ExpansionTile(
                      title: const Text('Registry (GitHub Gist) — Admin'),
                      childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      children: [
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Gist ID (registry.json)',
                          ),
                          controller: TextEditingController(
                            text: gistIdSetting ?? '',
                          ),
                          onChanged: (v) => gistIdSetting = v.trim(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'GitHub token (optional, gist scope)',
                          ),
                          controller: TextEditingController(
                            text: githubTokenSetting ?? '',
                          ),
                          onChanged: (v) => githubTokenSetting = v.trim(),
                          obscureText: true,
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Filebin bin name (optional)',
                                ),
                                controller: TextEditingController(
                                  text: filebinBinSetting ?? '',
                                ),
                                onChanged: (v) => filebinBinSetting = v.trim(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                final gen = 'wowui-${_generateSyncId(8)}';
                                setState(() => filebinBinSetting = gen);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Generated bin: $gen'),
                                  ),
                                );
                              },
                              child: const Text('Generate'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _saveSettings,
                              child: const Text('Save'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                // create a new gist if token provided
                                if (githubTokenSetting == null ||
                                    githubTokenSetting!.isEmpty) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'GitHub token required to create a gist',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final id = await createRegistryGist(
                                  githubTokenSetting!,
                                );
                                if (id == null) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to create gist'),
                                    ),
                                  );
                                  return;
                                }
                                // Use the state context after awaiting the create call
                                if (!mounted) return;
                                setState(() => gistIdSetting = id);
                                await _saveSettings();
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Gist created and saved'),
                                  ),
                                );
                              },
                              child: const Text('Create gist'),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: newAdminPasswordController,
                                decoration: const InputDecoration(
                                  labelText: 'New Admin password',
                                ),
                                obscureText: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                final p = newAdminPasswordController.text;
                                if (p.isEmpty) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Password cannot be empty'),
                                    ),
                                  );
                                  return;
                                }
                                _setAdminPassword(p);
                                newAdminPasswordController.clear();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Admin password updated'),
                                  ),
                                );
                              },
                              child: const Text('Set admin password'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                // test fetch
                                if (gistIdSetting == null ||
                                    gistIdSetting!.isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Set Gist ID first'),
                                    ),
                                  );
                                  return;
                                }
                                final messenger = ScaffoldMessenger.of(context);
                                final url = await fetchUrlFromRegistry(
                                  syncId ?? '',
                                );
                                if (url == null) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No registry entry found for current Sync ID',
                                      ),
                                    ),
                                  );
                                } else {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Found URL: $url')),
                                  );
                                }
                              },
                              child: const Text('Test fetch'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                setState(() => adminUnlocked = false);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Admin locked')),
                                );
                              },
                              child: const Text('Lock'),
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  final cfgText =
                      (gistIdSetting != null && gistIdSetting!.isNotEmpty)
                      ? 'Registry configured'
                      : 'Registry not configured';
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(cfgText),
                      ElevatedButton(
                        onPressed: () => _onAdminPressed(),
                        child: const Text('Admin'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
