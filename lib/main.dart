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

  // Optional: create a gist and put its id here if you want the app to update a central gist.
  // Otherwise the app will still upload to transfer.sh and show the returned URL locally.
  // To enable GitHub registry updates, set a GITHUB_TOKEN environment variable and a GIST_ID.
  static const GIST_ID = '<YOUR_GIST_ID_HERE>';
  static const GITHUB_TOKEN_ENV = 'GITHUB_TOKEN';

  @override
  void initState() {
    super.initState();
    _loadOrCreateSyncId();
    _attemptAutoDetect();
  }

  final TextEditingController syncIdController = TextEditingController();

  @override
  void dispose() {
    syncIdController.dispose();
    super.dispose();
  }

  Future<File> _getLocalFile(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, name));
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

  Future<String?> uploadToTransferSh(File file) async {
    try {
      final url = Uri.parse('https://transfer.sh/${p.basename(file.path)}');
      final bytes = await file.readAsBytes();
      final resp = await http.put(
        url,
        body: bytes,
        headers: {'Max-Downloads': '10'},
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return resp.body.trim();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateRegistryOnGithub(String id, String transferUrl) async {
    if (GIST_ID == '<YOUR_GIST_ID_HERE>') return false;
    final token = Platform.environment[GITHUB_TOKEN_ENV];
    if (token == null || token.isEmpty) return false;

    final gistApi = Uri.parse('https://api.github.com/gists/$GIST_ID');
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
    if (GIST_ID == '<YOUR_GIST_ID_HERE>') return null;
    final gistApi = Uri.parse('https://api.github.com/gists/$GIST_ID');
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
          duration: Duration(seconds: 60),
        ),
      );
      setState(() => isWorking = true);
      final url = await uploadToTransferSh(zip);
      setState(() => isWorking = false);
      if (url == null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload failed.')));
        return;
      }

      // attempt to update registry (best-effort)
      final did = await updateRegistryOnGithub(syncId ?? '', url!);

      // show the result and copy url to clipboard for convenience
      await Clipboard.setData(ClipboardData(text: url!));
      final msg = did
          ? 'Upload succeeded and registry updated. URL copied to clipboard.'
          : 'Upload succeeded. URL copied to clipboard.';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

      // show dialog with link and copy/open actions
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Text('Link:'), SelectableText(url!)],
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
                  url!,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WaddonSync')),
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
              const Text(
                'Using transfer.sh for uploads and a public GitHub gist as a small registry. To enable auto-update of the registry, set a GITHUB_TOKEN environment variable and configure the GIST_ID constant.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
