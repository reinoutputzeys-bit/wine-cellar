import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'data.dart';

/// Always points to Google's newest Flash model (free tier).
const String defaultModel = 'gemini-flash-latest';

/// What the online lookup found. Every field may be null.
class WineInfo {
  WineInfo(this.raw);

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
  "country": country in English (string),
  "region": region / appellation (string),
  "grapes": grape varieties, comma separated (string),
  "alcohol": e.g. "14.5%" (string),
  "drink_from": first year it is good to drink (number),
  "drink_until": last year it is at its best (number),
  "price_eur": typical retail price per bottle in euro (number),
  "pairing": food pairings, short and comma separated (string),
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
        'generationConfig': {'responseMimeType': 'application/json'},
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
    } catch (e) {
      throw LookupException('Lookup failed: $e');
    }

    final text = utf8.decode(resp.bodyBytes);
    Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw LookupException('Unexpected answer (${resp.statusCode}).');
    }

    if (resp.statusCode != 200) {
      final err = data['error'];
      final msg = err is Map ? (err['message'] ?? '').toString() : text;
      if (resp.statusCode == 400 && msg.toLowerCase().contains('api key')) {
        throw LookupException('The API key is not valid. Check it in Settings.');
      }
      if (resp.statusCode == 403) {
        throw LookupException('The API key is not allowed to do this. Check it in Settings.');
      }
      if (resp.statusCode == 429) {
        throw LookupException(useGoogleSearch
            ? 'Google Search is not included in the free tier. Turn it off in Settings.'
            : 'Free limit reached for now. Try again in a minute (or tomorrow).');
      }
      if (resp.statusCode == 404) {
        throw LookupException('Model "$model" not found. Check the model in Settings.');
      }
      throw LookupException('Lookup failed (${resp.statusCode}): $msg');
    }

    final candidates = (data['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      throw LookupException('Could not find details for this wine.');
    }
    final content = (candidates.first as Map)['content'];
    final outParts = content is Map ? (content['parts'] as List?) ?? const [] : const [];
    final answer = outParts
        .whereType<Map>()
        .where((p) => p['text'] != null && p['thought'] != true)
        .map((p) => p['text'].toString())
        .join('\n');

    final start = answer.indexOf('{');
    final end = answer.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw LookupException('Could not find details for this wine.');
    }
    try {
      final json = jsonDecode(answer.substring(start, end + 1));
      if (json is Map<String, dynamic>) return WineInfo(json);
    } catch (_) {}
    throw LookupException('Could not read the details that were found.');
  }
}
