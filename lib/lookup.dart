import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'data.dart';

const String defaultModel = 'claude-sonnet-5-5';

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

/// Asks Claude (with web search) to identify the wine from the label photo
/// and/or the details typed so far, and to fill in everything it can find.
class WineLookup {
  static const _system = '''
You are a wine expert helping someone catalogue their home wine cellar in Belgium.
Identify the exact wine from the label photo and/or the details given, then search the web
(Vivino, Wine-Searcher, the producer's own website, wine shops, reviews) to complete the details.
Reply with ONLY one JSON object, no other text, using exactly these keys:
{
  "name": wine name without producer and vintage (string),
  "producer": winery / château / winemaker (string),
  "vintage": year as number, or null if non-vintage or unreadable,
  "type": one of "Red", "White", "Sparkling", "Other" (rosé, sweet, fortified = "Other"),
  "country": country in English (string),
  "region": region / appellation (string),
  "grapes": grape varieties, comma separated (string),
  "alcohol": e.g. "14.5%" (string),
  "drink_from": first year it is good to drink (number),
  "drink_until": last year it is at its best (number),
  "price_eur": typical retail price per bottle in euro (number),
  "pairing": food pairings, short and comma separated (string),
  "description": 2-3 sentences about style and taste, in your own words (string),
  "confidence": "high", "medium" or "low" (how sure you are it is this exact wine)
}
Use null for anything you cannot find. Never invent values.''';

  static Future<WineInfo> lookup({
    required String apiKey,
    String model = defaultModel,
    String? photoPath,
    String name = '',
    String producer = '',
    String vintage = '',
  }) async {
    final content = <Map<String, dynamic>>[];
    if (photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync()) {
      final bytes = await File(photoPath).readAsBytes();
      content.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': base64Encode(bytes),
        },
      });
    }
    final known = [
      if (name.trim().isNotEmpty) 'Name: ${name.trim()}',
      if (producer.trim().isNotEmpty) 'Producer: ${producer.trim()}',
      if (vintage.trim().isNotEmpty) 'Vintage: ${vintage.trim()}',
    ];
    if (content.isEmpty && known.isEmpty) {
      throw LookupException('Add a photo or type at least the name first.');
    }
    content.add({
      'type': 'text',
      'text': known.isEmpty
          ? 'Which wine is this? Fill in all the details.'
          : 'Details I already know:\n${known.join('\n')}\n\nFill in all the details.',
    });

    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': content},
    ];

    for (var round = 0; round < 4; round++) {
      final http.Response resp;
      try {
        resp = await http
            .post(
              Uri.parse('https://api.anthropic.com/v1/messages'),
              headers: {
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
                'content-type': 'application/json',
              },
              body: jsonEncode({
                'model': model,
                'max_tokens': 2500,
                'system': _system,
                'messages': messages,
                'tools': [
                  {
                    'type': 'web_search_20250305',
                    'name': 'web_search',
                    'max_uses': 5,
                  }
                ],
              }),
            )
            .timeout(const Duration(seconds: 120));
      } on SocketException {
        throw LookupException('No internet connection.');
      } catch (e) {
        throw LookupException('Lookup failed: $e');
      }

      final body = utf8.decode(resp.bodyBytes);
      Map<String, dynamic> data;
      try {
        data = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw LookupException('Unexpected answer (${resp.statusCode}).');
      }
      if (resp.statusCode != 200) {
        final err = data['error'];
        final msg = err is Map ? err['message'] : null;
        if (resp.statusCode == 401) {
          throw LookupException('The API key is not valid. Check it in Settings.');
        }
        throw LookupException('Lookup failed (${resp.statusCode}): ${msg ?? body}');
      }

      final blocks = (data['content'] as List?) ?? const [];
      if (data['stop_reason'] == 'pause_turn') {
        // Long web search: let it continue where it stopped.
        messages.add({'role': 'assistant', 'content': blocks});
        continue;
      }

      final text = blocks
          .whereType<Map>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'].toString())
          .join('\n');
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) {
        throw LookupException('Could not find details for this wine.');
      }
      try {
        final json = jsonDecode(text.substring(start, end + 1));
        if (json is Map<String, dynamic>) return WineInfo(json);
      } catch (_) {}
      throw LookupException('Could not read the details that were found.');
    }
    throw LookupException('The search took too long. Please try again.');
  }
}
