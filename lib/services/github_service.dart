import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class GitHubService {
  final Function(String) log;

  GitHubService(this.log);

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

  Future<bool> updateRegistry({
    required String gistId,
    required String? token,
    required String id,
    required String transferUrl,
    String? expires,
    String? provider,
    String? extra,
  }) async {
    if (gistId.isEmpty) return false;
    final authToken = token ?? Platform.environment['GITHUB_TOKEN'];
    if (authToken == null || authToken.isEmpty) return false;

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
        'provider': provider ?? 'filebin',
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
          'Authorization': 'token $authToken',
          'Content-Type': 'application/json',
        },
        body: patchBody,
      );

      return patchResp.statusCode >= 200 && patchResp.statusCode < 300;
    } catch (e) {
      return false;
    }
  }

  Future<String?> fetchUrlFromRegistry({
    required String gistId,
    required String id,
  }) async {
    if (gistId.isEmpty) return null;

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

      final tmp = File('${Directory.systemTemp.path}/${url.split('/').last}');
      await tmp.writeAsBytes(resp.bodyBytes);
      return tmp;
    } catch (e) {
      await log('downloadUrlToTemp error: $e');
      return null;
    }
  }
}
