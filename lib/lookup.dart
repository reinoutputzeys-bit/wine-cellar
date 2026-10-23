import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'data.dart';

/// Always points to Google's newest Flash model (free tier).
const String defaultModel = 'gemini-flash-latest';

/// What the online lookup found. Every field may be null.
class WineInfo {
  WineInfo(Map<String, dynamic> source)
      : raw = {
          for (final e in source.entries)
            e.key.toLowerCase().replaceAll(' ', '_'): e.value
        };

  final Map<String, dynamic> raw;

  String? str(String k) {
    final v = raw[k];
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null' || s.toLowerCase() == 'unknown') {
      return null;
    }
    return s;
  }

  int? integer(String k) {
    final v = raw[k];
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  double? number(String k) {
    final v = raw[k];
    if (v is num) return v.toDouble();
    if (v is String) return parseMoney(v);
    return null;
  }
}

class LookupException implements Exception {
  LookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Asks Google Gemini to identify the wine from the label photo and/or the
/// details typed so far, and to fill in everything it knows.
class WineLookup {
  static const _system = '''
You are a wine expert helping someone catalogue their home wine cellar in Belgium.
Identify the exact wine from the label photo and/or the details given, and give all the details you know about it.
Reply with ONLY one JSON object, no other text, using exactly these keys:
{
  "name": wine name without producer and vintage (string),
  "producer": winery / château / winemaker (string),
  "vintage": year as number, or null if non-vintage or unreadable,
  "type": one of "Red", "White", "Sparkling", "Other" (rosé, sweet, dessert, fortified = "Other"),
  "country": country in English, e.g. France, Italy, Hungary, Czech Republic, United States (string),
  "region": region / appellation (string),
  "grapes": grape varieties, comma separated (string),
  "alcohol": e.g. "14.5%" (string),
  "drink_from": first year it is good to drink (number),
  "drink_until": last year it is at its best (number),
  "price_eur": typical retail price per bottle in euro (number),
  "pairing": comma separated; first the matching words from this list: Apero, Fish, Lamb, Beef, Game, Poultry, Spaghetti, Cheese, Dessert, Other; then at most 2 specific dishes (string),
  "description": 2-3 sentences about style and taste (string),
  "confidence": "high", "medium" or "low" (how sure you are it is this exact wine)
}
Use null for anything you do not know. Never invent values.''';

  static Future<WineInfo> lookup({
    required String apiKey,
    String model = defaultModel,
    bool useGoogleSearch = false,
    String? photoPath,
    String name = '',
    String producer = '',
    String vintage = '',
  }) async {
    final parts = <Map<String, dynamic>>[];
    if (photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync()) {
      final bytes = await File(photoPath).readAsBytes();
      parts.add({
        'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(bytes)},
      });
    }
    final known = [
      if (name.trim().isNotEmpty) 'Name: ${name.trim()}',
      if (producer.trim().isNotEmpty) 'Producer: ${producer.trim()}',
      if (vintage.trim().isNotEmpty) 'Vintage: ${vintage.trim()}',
    ];
    if (parts.isEmpty && known.isEmpty) {
      throw LookupException('Add a photo or type at least the name first.');
    }
    parts.add({
      'text': known.isEmpty
          ? 'Which wine is this? Give all the details.'
          : 'Details I already know:\n${known.join('\n')}\n\nGive all the details.',
    });

    final models = <String>[
      model,
      for (final m in _fallbackModels)
        if (m != model) m,
    ];
    LookupException? last;
    var busy = false;
    for (final m in models) {
      // A busy model gets one more try after a short pause.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await _ask(apiKey, m, parts, useGoogleSearch);
        } on _Busy catch (e) {
          busy = true;
          last = LookupException(e.message);
          if (attempt == 0) await Future<void>.delayed(const Duration(seconds: 3));
        } on _TryNextModel catch (e) {
          last = LookupException(e.message);
          break;
        }
      }
    }
    if (busy) {
      throw LookupException(
          "Google's free AI is very busy right now. Please try again in a few minutes.");
    }
    throw last ?? LookupException('Lookup failed.');
  }

  /// Tried in this order when a model is not available for the key.
  static const _fallbackModels = [
    'gemini-flash-latest',
    'gemini-flash-lite-latest',
    'gemini-3.6-flash',
    'gemini-3.5-flash',
  ];

  static const Map<String, dynamic> _schema = {
    'type': 'OBJECT',
    'properties': {
      'name': {'type': 'STRING', 'nullable': true},
      'producer': {'type': 'STRING', 'nullable': true},
      'vintage': {'type': 'INTEGER', 'nullable': true},
      'type': {
        'type': 'STRING',
        'nullable': true,
        'enum': ['Red', 'White', 'Sparkling', 'Other'],
      },
      'country': {'type': 'STRING', 'nullable': true},
      'region': {'type': 'STRING', 'nullable': true},
      'grapes': {'type': 'STRING', 'nullable': true},
      'alcohol': {'type': 'STRING', 'nullable': true},
      'drink_from': {'type': 'INTEGER', 'nullable': true},
      'drink_until': {'type': 'INTEGER', 'nullable': true},
      'price_eur': {'type': 'NUMBER', 'nullable': true},
      'pairing': {'type': 'STRING', 'nullable': true},
      'description': {'type': 'STRING', 'nullable': true},
      'confidence': {
        'type': 'STRING',
        'nullable': true,
        'enum': ['high', 'medium', 'low'],
      },
    },
  };

  static Future<WineInfo> _ask(String apiKey, String model,
      List<Map<String, dynamic>> parts, bool useGoogleSearch) async {
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': _system}
        ]
      },
      'contents': [
        {'role': 'user', 'parts': parts}
      ],
      if (useGoogleSearch)
        'tools': [
          {'google_search': <String, dynamic>{}}
        ]
      else
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': _schema,
        },
    };

    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
            headers: {
              'x-goog-api-key': apiKey,
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
    } on SocketException {
      throw LookupException('No internet connection.');
    } on TimeoutException {
      throw LookupException('Google took too long to answer. Please try again.');
    } catch (e) {
      throw LookupException('Lookup failed: $e');
    }

    final text = utf8.decode(resp.bodyBytes);
    Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw LookupException('Unexpected answer from Google (${resp.statusCode}).');
    }

    if (resp.statusCode != 200) {
      final err = data['error'];
      final msg = err is Map ? (err['message'] ?? '').toString() : text;
      final status = err is Map ? (err['status'] ?? '').toString() : '';
      final detail = '(${resp.statusCode} $status) $msg'.trim();
      // Google is overloaded ("high demand"): wait, then try again or another model.
      if (resp.statusCode == 503 || resp.statusCode == 500 || resp.statusCode == 504) {
        throw _Busy('Google is busy: $detail');
      }
      // Model not available for this key: try the next one.
      if (resp.statusCode == 404 ||
          (resp.statusCode == 401 && msg.contains('ACCESS_TOKEN_TYPE_UNSUPPORTED')) ||
          (resp.statusCode == 400 && msg.toLowerCase().contains('model'))) {
        throw _TryNextModel('Model "$model" is not available: $detail');
      }
      if (resp.statusCode == 400 && msg.toLowerCase().contains('api key')) {
        throw LookupException('Google does not accept this key. Check it in Settings. $detail');
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw LookupException('Google refused the key. $detail');
      }
      if (resp.statusCode == 429) {
        throw LookupException(useGoogleSearch
            ? 'Google Search is not included in the free tier. Turn it off in Settings. $detail'
            : 'Free limit reached for now. Try again in a minute. $detail');
      }
      throw LookupException('Lookup failed $detail');
    }

    final candidates = (data['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      final block = (data['promptFeedback'] is Map)
          ? (data['promptFeedback'] as Map)['blockReason']
          : null;
      throw LookupException(
          'Google gave no answer${block == null ? '' : ' (blocked: $block)'}.');
    }
    final cand = candidates.first as Map;
    final content = cand['content'];
    final outParts =
        content is Map ? (content['parts'] as List?) ?? const [] : const [];
    final answer = outParts
        .whereType<Map>()
        .where((p) => p['text'] != null && p['thought'] != true)
        .map((p) => p['text'].toString())
        .join('\n');

    final start = answer.indexOf('{');
    final end = answer.lastIndexOf('}');
    if (start < 0 || end <= start) {
      final reason = cand['finishReason'];
      throw LookupException(
          'Google could not identify this wine${reason == null || reason == 'STOP' ? '' : ' ($reason)'}.');
    }
    try {
      final json = jsonDecode(answer.substring(start, end + 1));
      if (json is Map<String, dynamic>) return WineInfo(json);
    } catch (_) {}
    throw LookupException('Could not read the details Google sent back.');
  }

  /// Small text-only request to check that the key works.
  static Future<String> testKey(String apiKey, String model) async {
    final info = await lookup(
        apiKey: apiKey, model: model, name: 'Château Margaux', vintage: '2015');
    return info.str('producer') ?? info.str('name') ?? 'an answer';
  }
}

class _Busy implements Exception {
  _Busy(this.message);
  final String message;
}

class _TryNextModel implements Exception {
  _TryNextModel(this.message);
  final String message;
}
