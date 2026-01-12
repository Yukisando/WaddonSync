import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

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
          if (oldFolder.listSync().isEmpty)
            await oldFolder.delete(recursive: true);
        } catch (e) {}
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
        'adminHash': adminHash ?? '',
      };
      await f.writeAsString(json.encode(obj));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
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
    try {
      final url = Uri.parse('https://transfer.sh/${p.basename(file.path)}');
      final bytes = await file.readAsBytes();
      final resp = await http.put(
        url,
        body: bytes,
        headers: {'Max-Downloads': '10'},
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final returned = resp.body.trim();
        String? expires;
        // Try to find a header that indicates expiry or ttl
        for (final entry in resp.headers.entries) {
          final k = entry.key.toLowerCase();
          if (k.contains('expire') ||
              k.contains('ttl') ||
              k.contains('max') ||
              k.contains('cache')) {
            expires = entry.value;
            break;
          }
        }
        return {'url': returned, 'expires': expires};
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateRegistryOnGithub(
    String id,
    String transferUrl, {
    String? expires,
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
      registry[id] = {
        'url': transferUrl,
        'timestamp': DateTime.now().toIso8601String(),
        'expires': expires,
      };

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
      return null;
    }
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
    final outFile = await _getLocalFile('waddonsync_backup_$timestamp.zip');

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
        if (await cfg.exists())
          await addFileAt(p.join('WTF', 'Config.wtf'), cfg);
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
              (parts.contains('cache') || parts.contains('wdb')))
            continue;
          final store = p.join(
            'Interface',
            p.relative(entity.path, from: interfaceDir),
          );
          await addFileAt(store, entity);
        }
      }
    }

    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive)!;
    await outFile.writeAsBytes(zipData, flush: true);

    setState(() {
      lastZipPath = outFile.path;
      isWorking = false;
    });

    return outFile;
  }

  Future<void> handleCreateZip() async {
    if (wtfPath == null || interfacePath == null) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error while zipping: $e')));
    }
  }

  Future<void> handleUploadAndRegister() async {
    if (wtfPath == null || interfacePath == null) return;
    try {
      // make the user aware we are zipping first
      ScaffoldMessenger.of(context).showSnackBar(
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

      // start uploading
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploading to transfer.sh...'),
          duration: Duration(seconds: 120),
        ),
      );
      setState(() => isWorking = true);
      final uploadResult = await uploadToTransferSh(zip);
      setState(() => isWorking = false);
      if (uploadResult == null || uploadResult['url'] == null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload failed.')));
        return;
      }

      final url = uploadResult['url']!;
      final expires = uploadResult['expires'];

      // attempt to update registry (best-effort)
      final did = await updateRegistryOnGithub(
        syncId ?? '',
        url,
        expires: expires,
      );

      // show the result and copy url to clipboard for convenience
      await Clipboard.setData(ClipboardData(text: url));
      final msg = did
          ? 'Upload succeeded and registry updated. URL copied to clipboard.'
          : 'Upload succeeded. URL copied to clipboard.';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

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
                    : 'Note: transfer.sh links are temporary and may expire',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                Navigator.of(ctx).pop();
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () async {
                await Process.run('rundll32', [
                  'url.dll,FileProtocolHandler',
                  url,
                ]);
                Navigator.of(ctx).pop();
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
      setState(() => isWorking = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> handleSyncById(String id) async {
    if (id.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Fetching registry...')));
    final url = await fetchUrlFromRegistry(id);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No entry found for that ID.')),
      );
      return;
    }
    final file = await downloadUrlToTemp(url!);
    if (file == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to download file.')));
      return;
    }
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
            tooltip: 'Admin',
            icon: const Icon(Icons.settings),
            onPressed: () => _onAdminPressed(),
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
                    onPressed:
                        (wtfPath != null && interfacePath != null && !isWorking)
                        ? handleUploadAndRegister
                        : null,
                    child: isWorking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save & Upload'),
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
                      await Clipboard.setData(ClipboardData(text: syncId!));
                      ScaffoldMessenger.of(context).showSnackBar(
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
                      await _saveSyncId(newId);
                      ScaffoldMessenger.of(context).showSnackBar(
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
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _saveSettings,
                              child: const Text('Save'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                // create a new gist if token provided
                                if (githubTokenSetting == null ||
                                    githubTokenSetting!.isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
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
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to create gist'),
                                    ),
                                  );
                                  return;
                                }
                                setState(() => gistIdSetting = id);
                                await _saveSettings();
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Gist created and saved'),
                                  ),
                                );
                              },
                              child: const Text('Create gist'),
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
                                final url = await fetchUrlFromRegistry(
                                  syncId ?? '',
                                );
                                if (url == null) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No registry entry found for current Sync ID',
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
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
