import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'token_storage_service.dart';
import 'google_oauth_service.dart';

/// Google Drive service for uploading and downloading addon backups
class GoogleDriveService {
  final Function(String) log;
  final TokenStorageService _tokenStorage;
  final GoogleOAuthService _oauthService;

  AccessCredentials? _credentials;
  drive.DriveApi? _driveApi;
  http.Client? _httpClient; // Track HTTP client for proper cleanup

  // Folder name in Google Drive for storing backups
  static const String backupFolderName = 'WaddonSync Backups';
  String? _backupFolderId;

  GoogleDriveService(this.log)
    : _tokenStorage = TokenStorageService(log),
      _oauthService = GoogleOAuthService(log);

  /// Initializes the Drive service with stored credentials or prompts for authorization
  Future<bool> initialize() async {
    try {
      await log('Initializing Google Drive service...');

      // Check if we have stored credentials
      final hasCredentials = await _tokenStorage.hasCredentials();

      if (hasCredentials) {
        await log('Found stored credentials, loading...');
        _credentials = await _tokenStorage.loadCredentials();

        if (_credentials != null) {
          // Check if token needs refresh
          final isExpired = await _tokenStorage.isTokenExpired();

          if (isExpired && _credentials!.refreshToken != null) {
            await log('Access token expired, refreshing...');
            _credentials = await _oauthService.refreshAccessToken(
              _credentials!,
            );

            if (_credentials != null) {
              await _tokenStorage.saveCredentials(_credentials!);
            } else {
              await log('Token refresh failed, re-authorization required');
              return await _authorizeUser();
            }
          }
        } else {
          return await _authorizeUser();
        }
      } else {
        await log('No stored credentials found');
        return await _authorizeUser();
      }

      // Create Drive API client
      await _createDriveClient();

      // Ensure backup folder exists
      await _ensureBackupFolder();

      await log('Google Drive service initialized successfully');
      return true;
    } catch (e, st) {
      await log('Failed to initialize Google Drive service: $e\n$st');
      return false;
    }
  }

  /// Prompts user for Google authorization
  Future<bool> _authorizeUser() async {
    try {
      await log('User authorization required...');

      _credentials = await _oauthService.authorize();

      if (_credentials == null) {
        await log('Authorization failed');
        return false;
      }

      // Save credentials for future use
      await _tokenStorage.saveCredentials(_credentials!);

      return true;
    } catch (e, st) {
      await log('Authorization error: $e\n$st');
      return false;
    }
  }

  /// Creates an authenticated Drive API client
  Future<void> _createDriveClient() async {
    if (_credentials == null) {
      throw Exception('No credentials available');
    }

    // Close existing client if any
    _httpClient?.close();
    
    _httpClient = _AuthenticatedClient(_credentials!);
    _driveApi = drive.DriveApi(_httpClient!);
    await log('Drive API client created');
  }

  /// Ensures the backup folder exists in Google Drive
  Future<void> _ensureBackupFolder() async {
    try {
      if (_driveApi == null) {
        throw Exception('Drive API not initialized');
      }

      await log('Checking for backup folder...');

      // Search for existing folder
      final query =
          "name='$backupFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        _backupFolderId = fileList.files!.first.id;
        await log('Found existing backup folder: $_backupFolderId');
      } else {
        // Create folder
        await log('Creating backup folder...');
        final folder = drive.File()
          ..name = backupFolderName
          ..mimeType = 'application/vnd.google-apps.folder';

        final created = await _driveApi!.files.create(folder);
        _backupFolderId = created.id;
        await log('Created backup folder: $_backupFolderId');
      }
    } catch (e, st) {
      await log('Error ensuring backup folder: $e\n$st');
      rethrow;
    }
  }

  /// Uploads a file to Google Drive
  Future<Map<String, String?>?> uploadFile(File file) async {
    try {
      if (_driveApi == null) {
        await log('Drive API not initialized, initializing...');
        final initialized = await initialize();
        if (!initialized) {
          return {'error': 'Failed to initialize Google Drive'};
        }
      }

      final fileName = p.basename(file.path);
      final fileSize = await file.length();
      final sizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);

      await log('Uploading $fileName ($sizeMB MB) to Google Drive...');

      // Delete old backups (keep only most recent)
      await _deleteOldBackups();

      // Create file metadata
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [_backupFolderId!]
        ..description =
            'WaddonSync backup created on ${DateTime.now().toIso8601String()}';

      // Upload file
      final media = drive.Media(file.openRead(), fileSize);

      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id, name, webViewLink, size, createdTime',
      );

      await log('Upload successful!');
      await log('File ID: ${uploadedFile.id}');
      await log('File name: ${uploadedFile.name}');

      return {
        'fileId': uploadedFile.id,
        'fileName': uploadedFile.name,
        'size': uploadedFile.size?.toString(),
        'createdTime': uploadedFile.createdTime?.toIso8601String(),
        'provider': 'google_drive',
      };
    } catch (e, st) {
      final err = 'Google Drive upload failed: $e\n$st';
      await log(err);
      return {'error': err};
    }
  }

  /// Downloads a file from Google Drive
  Future<File?> downloadFile(String fileId, String savePath) async {
    try {
      if (_driveApi == null) {
        await log('Drive API not initialized, initializing...');
        final initialized = await initialize();
        if (!initialized) {
          await log('Failed to initialize Google Drive');
          return null;
        }
      }

      await log('Downloading file $fileId from Google Drive...');

      // Get file metadata
      final fileMetadata =
          await _driveApi!.files.get(fileId, $fields: 'name, size')
              as drive.File;

      await log(
        'Downloading ${fileMetadata.name} (${fileMetadata.size} bytes)...',
      );

      // Download file content
      final media =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      // Write to file
      final outputFile = File(savePath);
      final sink = outputFile.openWrite();

      await for (final chunk in media.stream) {
        sink.add(chunk);
      }

      await sink.close();

      await log('Download complete: $savePath');
      return outputFile;
    } catch (e, st) {
      await log('Download error: $e\n$st');
      return null;
    }
  }

  /// Lists all backups in Google Drive folder
  Future<List<Map<String, dynamic>>> listBackups() async {
    try {
      if (_driveApi == null) {
        await log('Drive API not initialized, initializing...');
        final initialized = await initialize();
        if (!initialized) {
          return [];
        }
      }

      await log('Listing backups...');

      final query = "'$_backupFolderId' in parents and trashed=false";
      final fileList = await _driveApi!.files.list(
        q: query,
        spaces: 'drive',
        orderBy: 'createdTime desc',
        $fields: 'files(id, name, size, createdTime, modifiedTime)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        await log('No backups found');
        return [];
      }

      final backups = fileList.files!
          .map(
            (file) => {
              'fileId': file.id,
              'name': file.name,
              'size': file.size,
              'createdTime': file.createdTime?.toIso8601String(),
              'modifiedTime': file.modifiedTime?.toIso8601String(),
            },
          )
          .toList();

      await log('Found ${backups.length} backup(s)');
      return backups;
    } catch (e, st) {
      await log('Error listing backups: $e\n$st');
      return [];
    }
  }

  /// Finds the most recent backup
  Future<String?> findLatestBackup() async {
    try {
      final backups = await listBackups();

      if (backups.isEmpty) {
        await log('No backups found');
        return null;
      }

      // Backups are already ordered by createdTime desc
      final latest = backups.first;
      await log('Latest backup: ${latest['name']} (${latest['fileId']})');

      return latest['fileId'] as String?;
    } catch (e, st) {
      await log('Error finding latest backup: $e\n$st');
      return null;
    }
  }

  /// Deletes old backups (keeps only the 3 most recent)
  Future<void> _deleteOldBackups() async {
    try {
      final backups = await listBackups();

      if (backups.length <= 3) {
        return; // Keep at least 3 backups
      }

      await log('Deleting ${backups.length - 3} old backup(s)...');

      // Delete all except the first 3 (most recent)
      for (var i = 3; i < backups.length; i++) {
        final fileId = backups[i]['fileId'] as String?;
        if (fileId != null) {
          try {
            await _driveApi!.files.delete(fileId);
            await log('Deleted old backup: ${backups[i]['name']}');
          } catch (e) {
            await log('Failed to delete backup $fileId: $e');
          }
        }
      }
    } catch (e, st) {
      await log('Error deleting old backups: $e\n$st');
    }
  }

  /// Deletes a single backup file by fileId. Returns true on success.
  Future<bool> deleteBackup(String fileId) async {
    try {
      if (_driveApi == null) {
        final initialized = await initialize();
        if (!initialized) return false;
      }

      await _driveApi!.files.delete(fileId);
      await log('Deleted backup: $fileId');
      return true;
    } catch (e, st) {
      await log('Failed to delete backup $fileId: $e\n$st');
      return false;
    }
  }

  /// Logs out and clears all stored credentials
  Future<bool> logout() async {
    try {
      await log('Logging out of Google Drive...');

      // Clean up HTTP client
      _httpClient?.close();
      _httpClient = null;
      
      _driveApi = null;
      _credentials = null;
      _backupFolderId = null;

      await _tokenStorage.clearCredentials();

      await log('Logout successful');
      return true;
    } catch (e, st) {
      await log('Logout error: $e\n$st');
      return false;
    }
  }

  /// Checks if user is currently authenticated
  Future<bool> isAuthenticated() async {
    return await _tokenStorage.hasCredentials();
  }
}

/// Authenticated HTTP client for Google APIs
class _AuthenticatedClient extends http.BaseClient {
  final AccessCredentials credentials;
  final http.Client _inner = http.Client();

  _AuthenticatedClient(this.credentials);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Add authorization header
    request.headers['Authorization'] =
        '${credentials.accessToken.type} ${credentials.accessToken.data}';

    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
