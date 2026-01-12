import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

/// Google OAuth 2.0 service for desktop applications
/// Handles the authorization code flow with local redirect
class GoogleOAuthService {
  final Function(String) log;

  // OAuth 2.0 credentials - you'll need to create these in Google Cloud Console
  // Go to: https://console.cloud.google.com/apis/credentials
  // Create OAuth 2.0 Client ID for Desktop application
  static const String clientId =
      '209451099455-h3s47j5q1b79g4t3m1aoh1bd8m091i5b.apps.googleusercontent.com';
  static const String clientSecret = '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';

  // Required scopes for Drive file access
  static const List<String> scopes = [
    'https://www.googleapis.com/auth/drive.file',
  ];

  GoogleOAuthService(this.log);

  /// Performs the OAuth 2.0 authorization code flow for desktop apps
  /// Returns AccessCredentials containing access and refresh tokens
  Future<AccessCredentials?> authorize() async {
    try {
      await log('Starting Google OAuth 2.0 authorization...');

      // Create client credentials
      final clientCredentials = ClientId(clientId, clientSecret);

      // Start local HTTP server to receive OAuth callback
      final redirectPort = await _findAvailablePort();
      final redirectUri = 'http://localhost:$redirectPort';

      await log('Starting local server on port $redirectPort...');

      // This will handle the OAuth flow
      final credentials = await _authorizeWithPrompt(
        clientCredentials,
        redirectUri,
        redirectPort,
      );

      if (credentials != null) {
        await log('Authorization successful!');
        await log('Access token expires: ${credentials.accessToken.expiry}');
        return credentials;
      }

      await log('Authorization failed or was cancelled');
      return null;
    } catch (e, st) {
      await log('OAuth authorization error: $e\n$st');
      return null;
    }
  }

  /// Refreshes an expired access token using the refresh token
  Future<AccessCredentials?> refreshAccessToken(
    AccessCredentials oldCredentials,
  ) async {
    try {
      await log('Refreshing access token...');

      final clientCredentials = ClientId(clientId, clientSecret);

      // Use the refresh token to get new credentials
      if (oldCredentials.refreshToken == null) {
        await log('No refresh token available');
        return null;
      }

      final client = http.Client();

      final response = await client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientCredentials.identifier,
          'client_secret': clientCredentials.secret!,
          'refresh_token': oldCredentials.refreshToken!,
          'grant_type': 'refresh_token',
        },
      );

      client.close();

      if (response.statusCode != 200) {
        await log(
          'Token refresh failed: ${response.statusCode} ${response.body}',
        );
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      final accessToken = data['access_token'] as String;
      final expiresIn = data['expires_in'] as int;
      final tokenType = data['token_type'] as String;
      final expiry = DateTime.now().toUtc().add(Duration(seconds: expiresIn));

      // Refresh token is usually not returned, so reuse the old one
      final refreshToken =
          data['refresh_token'] as String? ?? oldCredentials.refreshToken;

      final newCredentials = AccessCredentials(
        AccessToken(tokenType, accessToken, expiry),
        refreshToken,
        oldCredentials.scopes,
      );

      await log('Token refreshed successfully');
      await log('New expiry: ${newCredentials.accessToken.expiry}');
      return newCredentials;
    } catch (e, st) {
      await log('Token refresh error: $e\n$st');
      return null;
    }
  }

  /// Performs OAuth flow with browser prompt and local callback
  Future<AccessCredentials?> _authorizeWithPrompt(
    ClientId clientCredentials,
    String redirectUri,
    int redirectPort,
  ) async {
    HttpServer? server;

    try {
      // Start local HTTP server to receive the callback
      server = await HttpServer.bind('localhost', redirectPort);

      // Build authorization URL
      final authUrl = _buildAuthorizationUrl(clientCredentials, redirectUri);

      await log('Opening browser for authorization...');
      await log('If browser doesn\'t open, visit: $authUrl');

      // Open the authorization URL in the user's default browser
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await log('Could not launch browser. Please open manually: $authUrl');
      }

      // Wait for the OAuth callback
      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('Authorization timeout'),
      );

      // Extract authorization code from the callback
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      // Send response to browser
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('''
          <html>
            <body style="font-family: Arial; text-align: center; padding: 50px;">
              ${error != null ? '<h1>Authorization Failed</h1><p>Error: $error</p>' : '<h1>Authorization Successful!</h1><p>You can close this window and return to WaddonSync.</p>'}
            </body>
          </html>
        ''');
      await request.response.close();

      if (error != null) {
        await log('Authorization error: $error');
        return null;
      }

      if (code == null) {
        await log('No authorization code received');
        return null;
      }

      await log('Received authorization code, exchanging for tokens...');

      // Exchange authorization code for access and refresh tokens
      final credentials = await _exchangeCodeForTokens(
        clientCredentials,
        code,
        redirectUri,
      );

      return credentials;
    } catch (e, st) {
      await log('Authorization prompt error: $e\n$st');
      return null;
    } finally {
      await server?.close();
    }
  }

  /// Builds the Google OAuth 2.0 authorization URL
  String _buildAuthorizationUrl(
    ClientId clientCredentials,
    String redirectUri,
  ) {
    final params = {
      'client_id': clientCredentials.identifier,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      'access_type': 'offline', // Request refresh token
      'prompt': 'consent', // Force consent screen to get refresh token
    };

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    return 'https://accounts.google.com/o/oauth2/v2/auth?$query';
  }

  /// Exchanges authorization code for access and refresh tokens
  Future<AccessCredentials?> _exchangeCodeForTokens(
    ClientId clientCredentials,
    String code,
    String redirectUri,
  ) async {
    try {
      final client = http.Client();

      final response = await client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientCredentials.identifier,
          'client_secret': clientCredentials.secret!,
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
        },
      );

      client.close();

      if (response.statusCode != 200) {
        await log(
          'Token exchange failed: ${response.statusCode} ${response.body}',
        );
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      // Parse tokens
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String?;
      final expiresIn = data['expires_in'] as int;
      final tokenType = data['token_type'] as String;

      if (refreshToken == null) {
        await log(
          'Warning: No refresh token received. You may need to re-authorize later.',
        );
      }

      final expiry = DateTime.now().toUtc().add(Duration(seconds: expiresIn));

      return AccessCredentials(
        AccessToken(tokenType, accessToken, expiry),
        refreshToken,
        scopes,
      );
    } catch (e, st) {
      await log('Token exchange error: $e\n$st');
      return null;
    }
  }

  /// Finds an available port for the local OAuth callback server
  Future<int> _findAvailablePort() async {
    try {
      // Try common ports first
      for (final port in [8080, 8081, 8082, 3000, 3001]) {
        try {
          final server = await HttpServer.bind('localhost', port);
          await server.close();
          return port;
        } catch (e) {
          // Port in use, try next
        }
      }

      // Let the OS assign a random available port
      final server = await HttpServer.bind('localhost', 0);
      final port = server.port;
      await server.close();
      return port;
    } catch (e) {
      // Fallback to default
      return 8080;
    }
  }
}
