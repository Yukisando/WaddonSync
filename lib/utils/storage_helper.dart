import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageHelper {
  static Future<File> getLocalFile(String name) async {
    final dir = await getApplicationSupportDirectory();
    final appFolder = Directory(
      p.join(dir.parent.path, 'com.waddonsync', 'WaddonSync'),
    );
    if (!await appFolder.exists()) await appFolder.create(recursive: true);
    return File(p.join(appFolder.path, name));
  }

  static Future<File> getLogFile() async => await getLocalFile('app.log');

  static Future<void> appendLog(String message) async {
    try {
      final f = await getLogFile();
      final ts = DateTime.now().toIso8601String();
      final line = '[$ts] $message\n';
      await f.writeAsString(line, mode: FileMode.append, flush: true);
      // ignore: avoid_print
      print(line);
    } catch (e) {
      // best-effort logging
    }
  }

  static Future<String> readLogs({int maxChars = 64 * 1024}) async {
    try {
      final f = await getLogFile();
      if (!await f.exists()) return '';
      final s = await f.readAsString();
      if (s.length <= maxChars) return s;
      return '... (truncated) ...\n${s.substring(s.length - maxChars)}';
    } catch (e) {
      return 'Failed to read log: $e';
    }
  }

  static Future<String?> writeLogsToExportFile(String logs) async {
    try {
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final out = await getLocalFile('app_export_$ts.log');
      await out.writeAsString(logs, flush: true);
      return out.path;
    } catch (e) {
      await appendLog('Failed to write export logs: $e');
      return null;
    }
  }

  static Future<void> clearLogs() async {
    try {
      final f = await getLogFile();
      if (await f.exists()) {
        await f.writeAsString('', flush: true);
      }
    } catch (e) {
      // best effort
    }
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
