import 'dart:async';
import 'dart:io';
import 'dart:math';
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

  // Upload using curl as fallback (with retries and verification)
  Future<Map<String, String?>?> uploadViacurlVerified(
    File file,
    String bin,
  ) async {
    final name = p.basename(file.path);
    final url = 'https://filebin.net/$bin/';

    await log(
      'Attempting upload via curl (verified) with --fail and --retry flags...',
    );

    const int maxAttempts = 8;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final args = [
          '-X',
          'POST',
          '-F',
          'file=@${file.path}',
          '--max-time',
          '600', // 10 minutes
          '--connect-timeout',
          '30',
          '--http1.1',
          '--fail', // treat HTTP 4xx/5xx as failures (non-zero exit)
          '--retry',
          '6', // let curl do more retries for transient errors
          '--retry-delay',
          '5',
          '--retry-connrefused',
          '--retry-all-errors',
          '-w',
          '\n%{http_code}', // append HTTP code on last line
          url,
        ];
        await log('curl command: curl ${args.join(' ')}');
        final result = await Process.run('curl', args, runInShell: true);

        final stdoutStr = result.stdout.toString();
        final stderrStr = result.stderr.toString();

        await log('curl exit code: ${result.exitCode}');
        if (stdoutStr.isNotEmpty) await log('curl output: $stdoutStr');
        if (stderrStr.isNotEmpty) await log('curl stderr: $stderrStr');

        // Robustly extract an HTTP status code from stdout or stderr
        int? httpCode;
        final trimmedOut = stdoutStr.trim();
        if (trimmedOut.isNotEmpty) {
          final lines = trimmedOut.split(RegExp(r'\r?\n'));
          final lastLine = lines.isNotEmpty ? lines.last.trim() : '';
          if (RegExp(r'^\d{3}$').hasMatch(lastLine) ||
              RegExp(r'^\d{3}$').hasMatch(trimmedOut)) {
            // last line was just the HTTP code
            httpCode = int.tryParse(lastLine.replaceAll(RegExp(r'\D'), ''));
          } else {
            // fallback: find any 3-digit group in output and pick the last occurrence
            final all = RegExp(r'\b(\d{3})\b').allMatches(trimmedOut).toList();
            if (all.isNotEmpty) httpCode = int.tryParse(all.last.group(1)!);
            // last resort: look for common 5xx phrases
            if (httpCode == null &&
                trimmedOut.contains('Backend fetch failed')) {
              httpCode = 503;
            }
          }
        }
        if (httpCode == null && stderrStr.trim().isNotEmpty) {
          final allErr = RegExp(
            r'\b(\d{3})\b',
          ).allMatches(stderrStr.trim()).toList();
          if (allErr.isNotEmpty) {
            httpCode = int.tryParse(allErr.last.group(1)!);
          }
          if (httpCode == null && stderrStr.contains('Backend fetch failed')) {
            httpCode = 503;
          }
          httpCode = 503;
        }

        final uploadUrl = 'https://filebin.net/$bin/$name';

        // Handle retryable exit codes (network errors)
        if (result.exitCode == 56 ||
            result.exitCode == 7 ||
            result.exitCode == 28) {
          // Exit 56: Recv failure, 7: Failed to connect, 28: Timeout
          await log(
            'curl network error (exit ${result.exitCode}), attempt $attempt/$maxAttempts',
          );
          if (attempt < maxAttempts) {
            await Future.delayed(Duration(seconds: attempt * 3));
            continue;
          }
          return {
            'error':
                'curl upload failed after $maxAttempts attempts: exit ${result.exitCode} (network error)',
          };
        }

        if (httpCode != null && httpCode >= 200 && httpCode < 300) {
          // Verify the uploaded file is reachable
          try {
            final verify = await http
                .get(Uri.parse(uploadUrl))
                .timeout(const Duration(seconds: 10));
            if (verify.statusCode == 200) {
              await log(
                'curl upload verified: $uploadUrl (HTTP ${verify.statusCode})',
              );
              return {'url': uploadUrl, 'bin': bin, 'verified': 'true'};
            } else {
              await log(
                'Uploaded file not reachable (HTTP ${verify.statusCode}), attempt $attempt',
              );
            }
          } catch (e) {
            await log('Verification GET failed: $e (attempt $attempt)');
          }
        } else {
          if (httpCode != null && httpCode >= 500 && httpCode < 600) {
            final delaySec = min((1 << attempt) + Random().nextInt(4), 120);
            await log(
              'Server error (HTTP $httpCode) from curl response, attempt $attempt/$maxAttempts. Retrying in ${delaySec}s...',
            );
            if (attempt < maxAttempts) {
              await Future.delayed(Duration(seconds: delaySec));
            }
            continue;
          }

          return {
            'error':
                'curl upload failed: exit ${result.exitCode} http:$httpCode stdout:${stdoutStr.trim()} stderr:${stderrStr.trim()}',
          };
        }
      } catch (e, st) {
        await log('curl upload attempt $attempt failed: $e\n$st');
        if (attempt < maxAttempts) {
          final delaySec = min((1 << attempt) + Random().nextInt(4), 120);
          await log('Retrying in ${delaySec}s...');
          await Future.delayed(Duration(seconds: delaySec));
        }
      }
    }

    return {'error': 'curl upload failed after $maxAttempts attempts'};
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
        return await uploadViacurlVerified(file, bin);
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
        // Verify file is reachable; if not, try curl fallback
        try {
          final verify = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));
          if (verify.statusCode == 200) {
            await log('HTTP upload verified: $url (HTTP ${verify.statusCode})');
            return {'url': url, 'bin': bin};
          } else {
            await log(
              'HTTP upload not reachable (HTTP ${verify.statusCode}), falling back to curl',
            );
            return await uploadViacurlVerified(file, bin);
          }
        } catch (e) {
          await log('Verification GET failed: $e, falling back to curl');
          return await uploadViacurlVerified(file, bin);
        }
      }

      final err =
          'filebin responded with status ${streamed.statusCode}: $respBody';
      await log('Filebin upload failed: $err');

      // For certain recoverable server responses, try the curl fallback
      if (streamed.statusCode >= 500 ||
          streamed.statusCode == 405 ||
          streamed.statusCode == 429) {
        await log(
          'Server responded ${streamed.statusCode}. Trying curl fallback...',
        );
        return await uploadViacurlVerified(file, bin);
      }

      return {'error': err};
    } catch (e, st) {
      final err = 'Exception during filebin upload: $e\n$st';
      await log(err);

      if (e.toString().contains('SocketException') ||
          e.toString().contains('Write failed') ||
          e.toString().contains('Connection')) {
        await log('HTTP client failed. Trying curl fallback...');
        client?.close();
        return await uploadViacurlVerified(file, bin);
      }

      return {'error': err};
    } finally {
      client?.close();
    }
  }
}
