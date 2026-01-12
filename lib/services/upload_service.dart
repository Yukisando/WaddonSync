import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class UploadService {
  final Function(String) log;

  UploadService(this.log);

  // Test if we can reach filebin.net
  Future<bool> testFilebinConnection() async {
    try {
      await log('Testing connection to filebin.net...');
      final testUri = Uri.parse('https://filebin.net/');
      final response = await http
          .get(testUri)
          .timeout(const Duration(seconds: 10));
      await log('Connection test: HTTP ${response.statusCode}');
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      await log('Connection test failed: $e');
      return false;
    }
  }

  // Upload using curl as fallback
  Future<Map<String, String?>?> uploadViacurl(File file, String bin) async {
    try {
      final name = p.basename(file.path);
      final url = 'https://filebin.net/$bin/';

      await log('Attempting upload via curl...');

      final result = await Process.run('curl', [
        '-X',
        'POST',
        '-F',
        'file=@${file.path}',
        '--max-time',
        '600',
        '--connect-timeout',
        '30',
        '-w',
        '\\n%{http_code}',
        url,
      ], runInShell: true);

      await log('curl exit code: ${result.exitCode}');
      if (result.stdout.toString().isNotEmpty) {
        await log('curl output: ${result.stdout}');
      }
      if (result.stderr.toString().isNotEmpty) {
        await log('curl stderr: ${result.stderr}');
      }

      if (result.exitCode == 0) {
        final uploadUrl = 'https://filebin.net/$bin/$name';
        await log('curl upload succeeded: $uploadUrl');
        return {'url': uploadUrl, 'bin': bin};
      }

      return {
        'error':
            'curl failed with exit code ${result.exitCode}: ${result.stderr}',
      };
    } catch (e, st) {
      await log('curl upload failed: $e\\n$st');
      return {'error': 'curl not available or failed: $e'};
    }
  }

  // Upload to filebin.net via HTTP multipart
  Future<Map<String, String?>?> uploadToFilebin(File file, String bin) async {
    http.Client? client;

    try {
      final name = p.basename(file.path);
      final uri = Uri.parse('https://filebin.net/$bin/');
      final fileSize = await file.length();
      final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
      await log('Uploading ${file.path} ($sizeMB MB) to filebin $bin');

      if (fileSize > 50 * 1024 * 1024) {
        await log('WARNING: File is >50MB. Upload may be slow or fail.');
      }

      // Test connection first
      final canConnect = await testFilebinConnection();
      if (!canConnect) {
        await log('Connection test failed. Trying curl fallback...');
        return await uploadViacurl(file, bin);
      }

      client = http.Client();
      final req = http.MultipartRequest('POST', uri);

      final stream = file.openRead();
      final part = http.MultipartFile('file', stream, fileSize, filename: name);
      req.files.add(part);
      req.headers['Connection'] = 'keep-alive';

      final timeout = fileSize > 20 * 1024 * 1024
          ? const Duration(minutes: 20)
          : const Duration(minutes: 10);

      await log('Starting upload (timeout: ${timeout.inMinutes} min)...');
      final streamed = await client
          .send(req)
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException(
                'Upload timed out after ${timeout.inMinutes} minutes',
              );
            },
          );

      final respBody = await streamed.stream.bytesToString();
      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        final url = 'https://filebin.net/$bin/$name';
        await log('Filebin upload succeeded: $url');
        return {'url': url, 'bin': bin};
      }

      final err =
          'filebin responded with status ${streamed.statusCode}: $respBody';
      await log('Filebin upload failed: $err');
      return {'error': err};
    } catch (e, st) {
      final err = 'Exception during filebin upload: $e\n$st';
      await log(err);

      if (e.toString().contains('SocketException') ||
          e.toString().contains('Write failed') ||
          e.toString().contains('Connection')) {
        await log('HTTP client failed. Trying curl fallback...');
        client?.close();
        return await uploadViacurl(file, bin);
      }

      return {'error': err};
    } finally {
      client?.close();
    }
  }
}
