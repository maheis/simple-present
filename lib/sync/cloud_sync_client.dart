import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class CloudSyncException implements Exception {
  CloudSyncException(this.message);
  final String message;

  @override
  String toString() => 'CloudSyncException: $message';
}

class CloudAuthResult {
  CloudAuthResult({
    required this.accountId,
    required this.deviceId,
    required this.token,
  });

  final String accountId;
  final String deviceId;
  final String token;
}

class CloudSyncClient {
  CloudSyncClient({
    required this.serverBaseUrl,
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient();

  final String serverBaseUrl;
  final HttpClient _http;

  static final Ed25519 _ed25519 = Ed25519();
  static final Sha256 _sha256 = Sha256();

  static const List<String> _suggestionWords = <String>[
    'apfel',
    'berg',
    'fluss',
    'stern',
    'wald',
    'nebel',
    'licht',
    'fenster',
    'uhr',
    'pfad',
    'wolke',
    'stein',
    'feder',
    'anker',
    'kiesel',
    'hafen',
    'morgen',
    'abend',
    'wiese',
    'insel',
    'reise',
    'signal',
    'funke',
    'brise',
    'kompass',
    'marker',
    'quelle',
    'kette',
    'schritt',
    'bogen',
    'bruecke',
    'farbe',
    'code',
    'fokus',
    'horizont',
    'linie',
    'notiz',
    'projekt',
    'rhythmus',
    'spur',
    'tempo',
    'weg',
    'ziel',
    'zeit',
    'taste',
    'feld',
    'kristall',
    'echo',
    'puls',
    'kamera',
    'radio',
    'satellit',
    'module',
    'delta',
    'alpha',
    'beta',
    'gamma',
    'vektor',
    'matrix',
    'socket',
  ];

  static String suggestWordPhrase({Random? random}) {
    final rng = random ?? Random.secure();
    final words = List<String>.generate(
      9,
      (_) => _suggestionWords[rng.nextInt(_suggestionWords.length)],
    );
    return words.join(' ');
  }

  static String normalizeWordPhrase(String phrase) {
    final normalized = phrase
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s\-]'), '');
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length != 9) {
      throw CloudSyncException('Word phrase must contain exactly 9 words.');
    }
    return words.join(' ');
  }

  static Future<SimpleKeyPair> derivePairingKeyPair(String phrase) async {
    final normalized = normalizeWordPhrase(phrase);
    final seedMaterial = utf8.encode('simplepresent-pairing-seed|$normalized');
    final hash = await _sha256.hash(seedMaterial);
    return _ed25519.newKeyPairFromSeed(hash.bytes);
  }

  Future<CloudAuthResult> registerFirstClient({
    required String deviceName,
    required String phrase,
  }) async {
    final keyPair = await derivePairingKeyPair(phrase);
    final publicKey = await keyPair.extractPublicKey();

    final payload = <String, dynamic>{
      'name': deviceName,
      'pairing_public_key': base64Encode(publicKey.bytes),
    };

    final response = await _postJson('/register', payload);

    final createdAccountId = (response['account_id'] ?? '').toString();
    final createdDeviceId = (response['device_id'] ?? '').toString();
    final token = (response['token'] ?? '').toString();

    if (createdAccountId.isEmpty || createdDeviceId.isEmpty || token.isEmpty) {
      throw CloudSyncException('Server returned incomplete register response.');
    }

    return CloudAuthResult(
      accountId: createdAccountId,
      deviceId: createdDeviceId,
      token: token,
    );
  }

  Future<CloudAuthResult> pairClient({
    required String accountId,
    required String deviceName,
    required String phrase,
  }) async {
    final challengeResponse = await _postJson('/pair/challenge', <String, dynamic>{
      'account_id': accountId,
    });

    final challengeId = (challengeResponse['challenge_id'] ?? '').toString();
    if (challengeId.isEmpty) {
      throw CloudSyncException('Server did not return a challenge_id.');
    }

    final keyPair = await derivePairingKeyPair(phrase);
    final message = utf8.encode(
      'simplepresent-pair|$accountId|$challengeId|$deviceName',
    );
    final signature = await _ed25519.sign(message, keyPair: keyPair);

    final pairResponse = await _postJson('/pair', <String, dynamic>{
      'account_id': accountId,
      'name': deviceName,
      'challenge_id': challengeId,
      'signature': base64Encode(signature.bytes),
    });

    final createdDeviceId = (pairResponse['device_id'] ?? '').toString();
    final token = (pairResponse['token'] ?? '').toString();
    if (createdDeviceId.isEmpty || token.isEmpty) {
      throw CloudSyncException('Server returned incomplete pair response.');
    }

    return CloudAuthResult(
      accountId: accountId,
      deviceId: createdDeviceId,
      token: token,
    );
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$serverBaseUrl$path');
    final request = await _http.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode > 299) {
      throw CloudSyncException(
        'Server error ${response.statusCode} on $path: $body',
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw CloudSyncException('Server response is not a JSON object.');
    }
    return decoded;
  }
}
