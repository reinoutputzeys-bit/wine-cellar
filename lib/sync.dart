import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data.dart';

// ============================================================
// SHARED CELLAR (Google Firebase / Firestore, free plan)
//
// Every phone keeps its own copy of the cellar, so the app works offline.
// Changes are sent to Firestore and picked up by the other phone.
//   cellars/main/bottles/{uuid}   one document per wine entry
//   cellars/main/photos/{photoId} the bottle photo (base64 jpg)
// If both phones change the same wine, the most recent change wins.
// ============================================================

enum SyncPhase { off, idle, syncing, error }

class SyncState {
  const SyncState(this.phase, {this.message = '', this.lastSync});
  final SyncPhase phase;
  final String message;
  final DateTime? lastSync;
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Sync {
  Sync._();
  static final Sync instance = Sync._();

  /// Shown in the app bar and in Settings.
  final ValueNotifier<SyncState> state =
      ValueNotifier(const SyncState(SyncPhase.off));

  /// Called when bottles changed because of the other phone.
  VoidCallback? onRemoteChange;

  static const _cellar = 'main';
  static const _pageSize = 300;

  String? _idToken;
  DateTime? _tokenExpiry;
  bool _running = false;
  bool _again = false;
  Timer? _debounce;

  // ---------------- settings ----------------
  Future<String> _get(String k) async => (await CellarDb.getSetting(k)) ?? '';

  Future<bool> get isConnected async =>
      (await _get('sync_refresh')).isNotEmpty &&
      (await _get('sync_project')).isNotEmpty;

  Future<String> get email => _get('sync_email');
  Future<String> get project => _get('sync_project');

  Future<void> init() async {
    if (await isConnected) {
      final last = DateTime.tryParse(await _get('sync_last_ok'));
      state.value = SyncState(SyncPhase.idle, lastSync: last);
    }
  }

  // ---------------- connect / disconnect ----------------
  Future<void> connect({
    required String projectId,
    required String apiKey,
    required String email,
    required String password,
  }) async {
    final r = await _post(
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey'),
      {'email': email, 'password': password, 'returnSecureToken': true},
      auth: false,
    );
    final refresh = r['refreshToken'] as String?;
    if (refresh == null) throw SyncException('Sign-in failed.');
    _idToken = r['idToken'] as String?;
    _tokenExpiry = DateTime.now()
        .add(Duration(seconds: int.tryParse('${r['expiresIn']}') ?? 3600) - const Duration(minutes: 5));
    await CellarDb.setSetting('sync_project', projectId.trim());
    await CellarDb.setSetting('sync_api_key', apiKey.trim());
    await CellarDb.setSetting('sync_email', email.trim());
    await CellarDb.setSetting('sync_refresh', refresh);
    await CellarDb.setSetting('sync_cursor', '');
    state.value = const SyncState(SyncPhase.idle);
    final ok = await syncNow();
    if (!ok) throw SyncException(state.value.message);
  }

  Future<void> disconnect() async {
    await CellarDb.setSetting('sync_refresh', '');
    _idToken = null;
    state.value = const SyncState(SyncPhase.off);
  }

  // ---------------- triggers ----------------
  /// Called after every local change: sync a moment later.
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => syncNow());
  }

  /// Sends local changes and fetches the other phone's changes.
  /// Returns true if it worked (or sharing is off).
  Future<bool> syncNow() async {
    if (!await isConnected) return true;
    if (_running) {
      _again = true;
      return true;
    }
    _running = true;
    final last = state.value.lastSync;
    state.value = SyncState(SyncPhase.syncing, lastSync: last);
    try {
      var changed = false;
      do {
        _again = false;
        await _push();
        if (await _pull()) changed = true;
        if (await _fetchMissingPhotos()) changed = true;
      } while (_again);
      final now = DateTime.now();
      await CellarDb.setSetting('sync_last_ok', now.toIso8601String());
      state.value = SyncState(SyncPhase.idle, lastSync: now);
      if (changed) onRemoteChange?.call();
      return true;
    } on SocketException {
      state.value = SyncState(SyncPhase.error,
          message: 'No internet. Changes are sent later.', lastSync: last);
      return false;
    } on TimeoutException {
      state.value = SyncState(SyncPhase.error,
          message: 'No answer from the server. Changes are sent later.', lastSync: last);
      return false;
    } catch (e) {
      state.value = SyncState(SyncPhase.error, message: '$e', lastSync: last);
      return false;
    } finally {
      _running = false;
    }
  }

  // ---------------- push ----------------
  Future<void> _push() async {
    // Deleted entries.
    final deletes = await CellarDb.pendingDeletes();
    for (var i = 0; i < deletes.length; i += 200) {
      final chunk = deletes.skip(i).take(200).toList();
      final now = DateTime.now().millisecondsSinceEpoch;
      await _commit([
        for (final u in chunk)
          _write('bottles/$u', {'uuid': u, 'deleted': true, 'updated_at': now})
      ]);
      for (final u in chunk) {
        await CellarDb.clearPendingDelete(u);
      }
    }

    // New and changed entries.
    final rows = await CellarDb.dirtyRows();
    final ready = <Map<String, Object?>>[];
    for (final row in rows) {
      final uuid = row['uuid'] as String?;
      if (uuid == null) continue;
      var photoId = row['photo_id'] as String?;
      final path = row['photo_path'] as String?;
      if (photoId == null && path != null && path.isNotEmpty && File(path).existsSync()) {
        photoId = await _uploadPhoto(path);
        if (photoId != null) await CellarDb.setPhotoId(uuid, photoId);
      }
      ready.add({...row, 'photo_id': photoId});
    }
    for (var i = 0; i < ready.length; i += 200) {
      final chunk = ready.skip(i).take(200).toList();
      await _commit([
        for (final r in chunk) _write('bottles/${r['uuid']}', _bottleFields(r))
      ]);
      for (final r in chunk) {
        await CellarDb.markClean(
            r['uuid'] as String, r['updated_at'] as int?, r['photo_id'] as String?);
      }
    }
  }

  static const _syncedColumns = [
    'uuid', 'updated_at', 'added_at', 'status', 'name', 'producer', 'vintage',
    'type', 'drawer', 'quantity', 'notes', 'country', 'region', 'grapes',
    'alcohol', 'drink_from', 'drink_until', 'price', 'pairing', 'drink_with',
    'description', 'photo_id',
  ];

  Map<String, Object?> _bottleFields(Map<String, Object?> row) => {
        for (final c in _syncedColumns) c: row[c],
        'deleted': false,
      };

  Future<String?> _uploadPhoto(String path) async {
    final bytes = await File(path).readAsBytes();
    final data = base64Encode(bytes);
    if (data.length > 950000) return null; // too big for one document
    final id = newUuid();
    await _commit([_write('photos/$id', {'data': data}, stamp: false)]);
    return id;
  }

  // ---------------- pull ----------------
  /// Returns true if any local bottle changed.
  Future<bool> _pull() async {
    var cursor = await _get('sync_cursor');
    var changed = false;
    while (true) {
      final query = <String, dynamic>{
        'from': [
          {'collectionId': 'bottles'}
        ],
        if (cursor.isNotEmpty)
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'serverTime'},
              'op': 'GREATER_THAN_OR_EQUAL',
              'value': {'timestampValue': cursor},
            }
          },
        'orderBy': [
          {
            'field': {'fieldPath': 'serverTime'},
            'direction': 'ASCENDING'
          }
        ],
        'limit': _pageSize,
      };
      final res = await _postList(
          Uri.parse('${await _docsUrl()}/cellars/$_cellar:runQuery'),
          {'structuredQuery': query});
      final docs = res
          .whereType<Map>()
          .map((e) => e['document'])
          .whereType<Map>()
          .toList();
      String? newCursor;
      for (final doc in docs) {
        final fields = _decodeFields(doc['fields'] as Map? ?? const {});
        newCursor = fields['serverTime'] as String? ?? newCursor;
        if (await _apply(fields)) changed = true;
      }
      if (newCursor != null && newCursor != cursor) {
        cursor = newCursor;
        await CellarDb.setSetting('sync_cursor', cursor);
      }
      if (docs.length < _pageSize || newCursor == null) break;
      if (docs.length == _pageSize && newCursor == cursor) break; // safety
    }
    return changed;
  }

  /// Applies one remote document. Returns true if the local cellar changed.
  Future<bool> _apply(Map<String, Object?> f) async {
    final uuid = f['uuid'] as String?;
    if (uuid == null) return false;
    final remoteTime = (f['updated_at'] as int?) ?? 0;
    final local = await CellarDb.rowByUuid(uuid);
    final localTime = (local?['updated_at'] as int?) ?? 0;
    final localDirty = (local?['dirty'] as int?) == 1;

    // My own unsent change is newer: keep it, it will be sent.
    if (local != null && localDirty && localTime >= remoteTime) return false;

    if (f['deleted'] == true) {
      if (local == null) return false;
      await CellarDb.deleteFromRemote(uuid);
      return true;
    }
    if (local != null && !localDirty && localTime == remoteTime) return false;

    final row = <String, Object?>{
      for (final c in _syncedColumns) c: f[c],
    };
    final price = f['price'];
    row['price'] = price is num ? price.toDouble() : null;
    // Keep the local photo file if it is the same photo.
    final samePhoto = local != null && local['photo_id'] == row['photo_id'];
    row['photo_path'] = samePhoto ? local['photo_path'] : null;
    await CellarDb.putFromRemote(row);
    return true;
  }

  /// Downloads photos that are known but not on this phone yet.
  Future<bool> _fetchMissingPhotos() async {
    final rows = await CellarDb.rowsWithPhotoId();
    var changed = false;
    Directory? docs;
    for (final r in rows) {
      final path = r['photo_path'] as String?;
      if (path != null && path.isNotEmpty && File(path).existsSync()) continue;
      final id = r['photo_id'] as String;
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      try {
        final doc = await _getJson(
            Uri.parse('${await _docsUrl()}/cellars/$_cellar/photos/$id'));
        final f = _decodeFields(doc['fields'] as Map? ?? const {});
        final data = f['data'] as String?;
        if (data == null) continue;
        docs ??= await getApplicationDocumentsDirectory();
        final dest = p.join(docs.path, 'photo_$id.jpg');
        await File(dest).writeAsBytes(base64Decode(data));
        await CellarDb.setPhotoPath(uuid, dest);
        changed = true;
      } on SyncException {
        // Photo not there (yet); try again next time.
      }
    }
    return changed;
  }

  // ---------------- Firestore helpers ----------------
  Future<String> _docsUrl() async =>
      'https://firestore.googleapis.com/v1/projects/${await project}/databases/(default)/documents';

  Future<String> _docName(String path) async =>
      'projects/${await project}/databases/(default)/documents/cellars/$_cellar/$path';

  Map<String, dynamic> _write(String path, Map<String, Object?> fields,
          {bool stamp = true}) =>
      {
        '_path': path,
        'fields': fields,
        'stamp': stamp,
      };

  Future<void> _commit(List<Map<String, dynamic>> writes) async {
    if (writes.isEmpty) return;
    final out = <Map<String, dynamic>>[];
    for (final w in writes) {
      out.add({
        'update': {
          'name': await _docName(w['_path'] as String),
          'fields': {
            for (final e in (w['fields'] as Map<String, Object?>).entries)
              e.key: _encode(e.value)
          },
        },
        if (w['stamp'] == true)
          'updateTransforms': [
            {'fieldPath': 'serverTime', 'setToServerValue': 'REQUEST_TIME'}
          ],
      });
    }
    await _post(Uri.parse('${await _docsUrl()}:commit'), {'writes': out});
  }

  static Map<String, dynamic> _encode(Object? v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': '$v'};
    if (v is double) return {'doubleValue': v};
    return {'stringValue': v.toString()};
  }

  static Map<String, Object?> _decodeFields(Map fields) {
    final out = <String, Object?>{};
    fields.forEach((k, v) {
      if (v is! Map) return;
      if (v.containsKey('stringValue')) {
        out['$k'] = v['stringValue'] as String?;
      } else if (v.containsKey('integerValue')) {
        out['$k'] = int.tryParse('${v['integerValue']}');
      } else if (v.containsKey('doubleValue')) {
        out['$k'] = (v['doubleValue'] as num?)?.toDouble();
      } else if (v.containsKey('booleanValue')) {
        out['$k'] = v['booleanValue'] == true;
      } else if (v.containsKey('timestampValue')) {
        out['$k'] = v['timestampValue'] as String?;
      } else {
        out['$k'] = null;
      }
    });
    return out;
  }

  // ---------------- HTTP + sign-in ----------------
  Future<String> _token() async {
    if (_idToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _idToken!;
    }
    final key = await _get('sync_api_key');
    final refresh = await _get('sync_refresh');
    if (refresh.isEmpty) throw SyncException('Not connected.');
    final resp = await http
        .post(Uri.parse('https://securetoken.googleapis.com/v1/token?key=$key'),
            body: {'grant_type': 'refresh_token', 'refresh_token': refresh})
        .timeout(const Duration(seconds: 30));
    final data = _json(resp);
    if (resp.statusCode != 200) {
      throw SyncException(
          'Signed out (${_errorText(data)}). Connect again in Settings.');
    }
    _idToken = data['id_token'] as String?;
    final newRefresh = data['refresh_token'] as String?;
    if (newRefresh != null) await CellarDb.setSetting('sync_refresh', newRefresh);
    _tokenExpiry = DateTime.now().add(
        Duration(seconds: int.tryParse('${data['expires_in']}') ?? 3600) -
            const Duration(minutes: 5));
    return _idToken!;
  }

  Map<String, dynamic> _json(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) return d;
      return {'_list': d};
    } catch (_) {
      return {};
    }
  }

  String _errorText(Map<String, dynamic> data) {
    final e = data['error'];
    if (e is Map) return '${e['message'] ?? e['status'] ?? e}';
    if (e is String) return e;
    return 'unknown error';
  }

  SyncException _httpError(int code, Map<String, dynamic> data) {
    final msg = _errorText(data);
    if (msg.contains('EMAIL_NOT_FOUND') ||
        msg.contains('INVALID_PASSWORD') ||
        msg.contains('INVALID_LOGIN_CREDENTIALS')) {
      return SyncException('Wrong email or password.');
    }
    if (msg.contains('API key not valid') || msg.contains('API_KEY_INVALID')) {
      return SyncException('The Web API key is not right.');
    }
    if (code == 403 || msg.contains('PERMISSION_DENIED')) {
      return SyncException(
          'No permission. Check that your email is in the Firestore rules. ($msg)');
    }
    if (code == 404) {
      return SyncException(
          'Not found. Check the Project ID and that the Firestore database exists. ($msg)');
    }
    return SyncException('Sync failed ($code): $msg');
  }

  Map<String, String> _headers(String? token) => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _post(Uri url, Map<String, dynamic> body,
      {bool auth = true}) async {
    final token = auth ? await _token() : null;
    final r = await http
        .post(url, headers: _headers(token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    final data = _json(r);
    if (r.statusCode != 200) throw _httpError(r.statusCode, data);
    return data;
  }

  Future<List<dynamic>> _postList(Uri url, Map<String, dynamic> body) async {
    final token = await _token();
    final r = await http
        .post(url, headers: _headers(token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    final data = _json(r);
    if (r.statusCode != 200) throw _httpError(r.statusCode, data);
    final list = data['_list'];
    return list is List ? list : const [];
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final token = await _token();
    final r = await http
        .get(url, headers: _headers(token))
        .timeout(const Duration(seconds: 60));
    final data = _json(r);
    if (r.statusCode != 200) throw _httpError(r.statusCode, data);
    return data;
  }
}
