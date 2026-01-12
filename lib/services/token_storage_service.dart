import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis_auth/auth_io.dart';

/// Securely stores and retrieves Google OAuth tokens
class TokenStorageService {
  final Function(String) log;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _accessTokenKey = 'google_access_token';
  static const String _refreshTokenKey = 'google_refresh_token';
  static const String _tokenExpiryKey = 'google_token_expiry';
  static const String _tokenTypeKey = 'google_token_type';
  static const String _scopesKey = 'google_scopes';

  TokenStorageService(this.log);

  /// Saves OAuth credentials securely
  Future<bool> saveCredentials(AccessCredentials credentials) async {
    try {
      await log('Saving credentials to secure storage...');

      // Store access token
      await _storage.write(
        key: _accessTokenKey,
        value: credentials.accessToken.data,
      );

      // Store refresh token (if available)
      if (credentials.refreshToken != null) {
        await _storage.write(
          key: _refreshTokenKey,
          value: credentials.refreshToken!,
        );
      }

      // Store expiry
      await _storage.write(
        key: _tokenExpiryKey,
        value: credentials.accessToken.expiry.toIso8601String(),
      );

      // Store token type
      await _storage.write(
        key: _tokenTypeKey,
        value: credentials.accessToken.type,
      );

      // Store scopes
      await _storage.write(
        key: _scopesKey,
        value: json.encode(credentials.scopes),
      );

      await log('Credentials saved successfully');
      return true;
    } catch (e, st) {
      await log('Error saving credentials: $e\n$st');
      return false;
    }
  }

  /// Retrieves stored OAuth credentials
  Future<AccessCredentials?> loadCredentials() async {
    try {
      await log('Loading credentials from secure storage...');

      // Read all token components
      final accessToken = await _storage.read(key: _accessTokenKey);
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      final expiryStr = await _storage.read(key: _tokenExpiryKey);
      final tokenType = await _storage.read(key: _tokenTypeKey);
      final scopesStr = await _storage.read(key: _scopesKey);

      // Validate required fields
      if (accessToken == null || expiryStr == null || tokenType == null) {
        await log('No valid credentials found in storage');
        return null;
      }

      // Parse expiry
      final expiry = DateTime.parse(expiryStr);

      // Parse scopes
      final scopes = scopesStr != null
          ? List<String>.from(json.decode(scopesStr) as List)
          : <String>[];

      // Create AccessCredentials
      final credentials = AccessCredentials(
        AccessToken(tokenType, accessToken, expiry),
        refreshToken,
        scopes,
      );

      await log('Credentials loaded successfully');

      // Check if token is expired
      if (credentials.accessToken.hasExpired) {
        await log('Warning: Access token has expired');
      } else {
        final remaining = credentials.accessToken.expiry.difference(
          DateTime.now(),
        );
        await log('Access token valid for ${remaining.inMinutes} more minutes');
      }

      return credentials;
    } catch (e, st) {
      await log('Error loading credentials: $e\n$st');
      return null;
    }
  }

  /// Checks if credentials exist in storage
  Future<bool> hasCredentials() async {
    try {
      final accessToken = await _storage.read(key: _accessTokenKey);
      return accessToken != null;
    } catch (e) {
      await log('Error checking credentials: $e');
      return false;
    }
  }

  /// Clears all stored credentials
  Future<bool> clearCredentials() async {
    try {
      await log('Clearing stored credentials...');

      await _storage.delete(key: _accessTokenKey);
      await _storage.delete(key: _refreshTokenKey);
      await _storage.delete(key: _tokenExpiryKey);
      await _storage.delete(key: _tokenTypeKey);
      await _storage.delete(key: _scopesKey);

      await log('Credentials cleared successfully');
      return true;
    } catch (e, st) {
      await log('Error clearing credentials: $e\n$st');
      return false;
    }
  }

  /// Checks if the access token is expired or about to expire
  Future<bool> isTokenExpired() async {
    try {
      final credentials = await loadCredentials();
      if (credentials == null) return true;

      // Consider token expired if it expires within the next 5 minutes
      final expiryBuffer = const Duration(minutes: 5);
      final expiryWithBuffer = credentials.accessToken.expiry.subtract(
        expiryBuffer,
      );

      return DateTime.now().isAfter(expiryWithBuffer);
    } catch (e) {
      await log('Error checking token expiry: $e');
      return true;
    }
  }
}
