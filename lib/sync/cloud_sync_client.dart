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
    this.notice,
  });

  final String accountId;
  final String deviceId;
  final String token;
  final String? notice;
}

class CloudAccountStatus {
  CloudAccountStatus({
    required this.archived,
    required this.lastActiveAt,
    required this.archiveAfterDays,
    required this.warningDays,
    required this.daysUntilArchive,
    required this.warning,
  });

  final bool archived;
  final int lastActiveAt;
  final int archiveAfterDays;
  final List<int> warningDays;
  final int daysUntilArchive;
  final bool warning;
}

class CloudStatePullResult {
  CloudStatePullResult({
    required this.payload,
    required this.modifiedAt,
    required this.version,
  });

  final Map<String, dynamic> payload;
  final int modifiedAt;
  final int version;
}

class CloudPulledItem {
  CloudPulledItem({
    required this.id,
    required this.payload,
    required this.modifiedAt,
    required this.version,
    required this.tombstone,
    required this.originDeviceId,
  });

  final String id;
  final Map<String, dynamic> payload;
  final int modifiedAt;
  final int version;
  final bool tombstone;
  final String originDeviceId;
}

class CloudSyncClient {
  CloudSyncClient({
    required this.serverBaseUrl,
    this.allowInsecureCertificates = false,
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient() {
    if (allowInsecureCertificates && serverBaseUrl.startsWith('https://')) {
      final uri = Uri.tryParse(serverBaseUrl);
      final expectedHost = uri?.host ?? '';
      final expectedPort = uri?.hasPort == true ? uri!.port : 443;
      _http.badCertificateCallback = (cert, host, port) {
        if (expectedHost.isEmpty) return true;
        if (host != expectedHost) return false;
        return port == expectedPort;
      };
    }
  }

  final String serverBaseUrl;
  final bool allowInsecureCertificates;
  final HttpClient _http;

  static final Ed25519 _ed25519 = Ed25519();
  static final Sha256 _sha256 = Sha256();
  static final AesGcm _aesGcm = AesGcm.with256bits();

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

  static Future<Map<String, dynamic>> encryptStatePayload({
    required Map<String, dynamic> payload,
    required String phrase,
  }) async {
    final normalized = normalizeWordPhrase(phrase);
    final keyMaterial = utf8.encode('simplepresent-e2e-state-key|$normalized');
    final hash = await _sha256.hash(keyMaterial);
    final secretKey = SecretKey(hash.bytes);

    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    final clearBytes = utf8.encode(jsonEncode(payload));
    final box = await _aesGcm.encrypt(
      clearBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return <String, dynamic>{
      'enc': 'v1',
      'alg': 'aes-gcm-256',
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  static Future<Map<String, dynamic>> decryptStatePayload({
    required Map<String, dynamic> encryptedPayload,
    required String phrase,
  }) async {
    if ((encryptedPayload['enc'] ?? '') != 'v1') {
      throw CloudSyncException('Unsupported encrypted payload format.');
    }

    final nonceB64 = (encryptedPayload['nonce'] ?? '').toString();
    final cipherB64 = (encryptedPayload['ciphertext'] ?? '').toString();
    final macB64 = (encryptedPayload['mac'] ?? '').toString();
    if (nonceB64.isEmpty || cipherB64.isEmpty || macB64.isEmpty) {
      throw CloudSyncException('Encrypted payload is incomplete.');
    }

    final normalized = normalizeWordPhrase(phrase);
    final keyMaterial = utf8.encode('simplepresent-e2e-state-key|$normalized');
    final hash = await _sha256.hash(keyMaterial);
    final secretKey = SecretKey(hash.bytes);

    final secretBox = SecretBox(
      base64Decode(cipherB64),
      nonce: base64Decode(nonceB64),
      mac: Mac(base64Decode(macB64)),
    );

    List<int> clearBytes;
    try {
      clearBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
    } catch (_) {
      throw CloudSyncException('Decryption failed (wrong phrase or corrupted data).');
    }

    final decoded = jsonDecode(utf8.decode(clearBytes));
    if (decoded is! Map<String, dynamic>) {
      throw CloudSyncException('Decrypted state is not a JSON object.');
    }
    return decoded;
  }

  Future<CloudAuthResult> registerFirstClient({
    required String deviceName,
    required String phrase,
    required String pin,
  }) async {
    final keyPair = await derivePairingKeyPair(phrase);
    final publicKey = await keyPair.extractPublicKey();

    final payload = <String, dynamic>{
      'name': deviceName,
      'pairing_public_key': base64Encode(publicKey.bytes),
      'pin': pin,
    };

    final response = await _postJson('/register', payload);

    final createdAccountId = (response['account_id'] ?? '').toString();
    final createdDeviceId = (response['device_id'] ?? '').toString();
    final token = (response['token'] ?? '').toString();
    final notice = (response['notice'] ?? '').toString();

    if (createdAccountId.isEmpty || createdDeviceId.isEmpty || token.isEmpty) {
      throw CloudSyncException('Server returned incomplete register response.');
    }

    return CloudAuthResult(
      accountId: createdAccountId,
      deviceId: createdDeviceId,
      token: token,
      notice: notice.isEmpty ? null : notice,
    );
  }

  Future<CloudAuthResult> pairClient({
    required String accountId,
    required String deviceName,
    required String phrase,
    required String pin,
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
      'pin': pin,
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
    return _postJsonAuthorized(path, payload, bearerToken: null);
  }

  Future<void> pushState({
    required String accountId,
    required String deviceId,
    required String token,
    required Map<String, dynamic> payload,
    required int modifiedAt,
    required int version,
    String itemId = 'simplepresent_state_v1',
  }) async {
    await _postJsonAuthorized(
      '/push',
      <String, dynamic>{
        'account_id': accountId,
        'items': [
          <String, dynamic>{
            'id': itemId,
            'payload': payload,
            'modified_at': modifiedAt,
            'tombstone': false,
            'origin_device_id': deviceId,
            'version': version,
          }
        ],
      },
      bearerToken: token,
    );
  }

  Future<void> pushItems({
    required String accountId,
    required String token,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return;
    await _postJsonAuthorized(
      '/push',
      <String, dynamic>{
        'account_id': accountId,
        'items': items,
      },
      bearerToken: token,
    );
  }

  Future<List<CloudPulledItem>> pullChangedItems({
    required String token,
    int since = 0,
    String idPrefix = '',
  }) async {
    final response = await _getJsonAuthorized(
      '/pull?since=$since',
      bearerToken: token,
    );
    final itemsRaw = response['items'];
    if (itemsRaw is! List) return const <CloudPulledItem>[];

    final latestById = <String, CloudPulledItem>{};

    for (final raw in itemsRaw) {
      if (raw is! Map) continue;
      final id = (raw['id'] ?? '').toString();
      if (id.isEmpty) continue;
      if (idPrefix.isNotEmpty && !id.startsWith(idPrefix)) continue;

      final modifiedAt = (raw['modified_at'] is num)
          ? (raw['modified_at'] as num).toInt()
          : int.tryParse(raw['modified_at']?.toString() ?? '') ?? 0;
      final version = (raw['version'] is num)
          ? (raw['version'] as num).toInt()
          : int.tryParse(raw['version']?.toString() ?? '') ?? 0;
      final tombstoneRaw = raw['tombstone'];
      final tombstone = tombstoneRaw == true || tombstoneRaw == 1;
      final originDeviceId = (raw['origin_device_id'] ?? '').toString();

      Map<String, dynamic> payload = <String, dynamic>{};
      final payloadRaw = raw['payload'];
      if (payloadRaw is Map) {
        payload = Map<String, dynamic>.from(payloadRaw.cast<String, dynamic>());
      }

      final candidate = CloudPulledItem(
        id: id,
        payload: payload,
        modifiedAt: modifiedAt,
        version: version,
        tombstone: tombstone,
        originDeviceId: originDeviceId,
      );

      final current = latestById[id];
      if (current == null || candidate.modifiedAt > current.modifiedAt) {
        latestById[id] = candidate;
      }
    }

    final out = latestById.values.toList();
    out.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
    return out;
  }

  Future<String?> getHealth() async {
    try {
      final uri = Uri.parse('$serverBaseUrl/health');
      final request = await _http.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode > 299) {
        return null;
      }
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final version = decoded['version'];
        if (version is String) return version;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<CloudAccountStatus> getAccountStatus({
    required String token,
  }) async {
    final response = await _getJsonAuthorized(
      '/account/status',
      bearerToken: token,
    );

    final archived = response['archived'] == true;
    final lastActiveAt = (response['last_active_at'] is num)
        ? (response['last_active_at'] as num).toInt()
        : int.tryParse(response['last_active_at']?.toString() ?? '') ?? 0;
    final archiveAfterDays = (response['archive_after_days'] is num)
        ? (response['archive_after_days'] as num).toInt()
        : int.tryParse(response['archive_after_days']?.toString() ?? '') ?? 0;
    final warningDaysRaw = response['warning_days'];
    final warningDays = warningDaysRaw is List
        ? warningDaysRaw
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toList()
        : const <int>[];
    final daysUntilArchive = (response['days_until_archive'] is num)
        ? (response['days_until_archive'] as num).toInt()
        : int.tryParse(response['days_until_archive']?.toString() ?? '') ?? -1;
    final warning = response['warning'] == true;

    return CloudAccountStatus(
      archived: archived,
      lastActiveAt: lastActiveAt,
      archiveAfterDays: archiveAfterDays,
      warningDays: warningDays,
      daysUntilArchive: daysUntilArchive,
      warning: warning,
    );
  }

  Future<CloudStatePullResult?> pullLatestState({
    required String token,
    int since = 0,
    String itemId = 'simplepresent_state_v1',
  }) async {
    final response = await _getJsonAuthorized(
      '/pull?since=$since',
      bearerToken: token,
    );
    final itemsRaw = response['items'];
    if (itemsRaw is! List) return null;

    Map<String, dynamic>? bestPayload;
    int bestModifiedAt = -1;
    int bestVersion = 0;

    for (final raw in itemsRaw) {
      if (raw is! Map) continue;
      final id = (raw['id'] ?? '').toString();
      if (id != itemId) continue;
      final payloadRaw = raw['payload'];
      if (payloadRaw is! Map) continue;

      final modifiedAt = (raw['modified_at'] is num)
          ? (raw['modified_at'] as num).toInt()
          : int.tryParse(raw['modified_at']?.toString() ?? '') ?? 0;
      final version = (raw['version'] is num)
          ? (raw['version'] as num).toInt()
          : int.tryParse(raw['version']?.toString() ?? '') ?? 0;

      if (modifiedAt > bestModifiedAt) {
        bestModifiedAt = modifiedAt;
        bestVersion = version;
        bestPayload = Map<String, dynamic>.from(payloadRaw.cast<String, dynamic>());
      }
    }

    if (bestPayload == null) return null;
    return CloudStatePullResult(
      payload: bestPayload,
      modifiedAt: bestModifiedAt,
      version: bestVersion,
    );
  }

  Future<Map<String, dynamic>> _postJsonAuthorized(
    String path,
    Map<String, dynamic> payload, {
    required String? bearerToken,
  }) async {
    final uri = Uri.parse('$serverBaseUrl$path');
    final request = await _http.postUrl(uri);
    request.headers.contentType = ContentType.json;
    if (bearerToken != null && bearerToken.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    }
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

  Future<Map<String, dynamic>> _getJsonAuthorized(
    String path, {
    required String bearerToken,
  }) async {
    final uri = Uri.parse('$serverBaseUrl$path');
    final request = await _http.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');

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
