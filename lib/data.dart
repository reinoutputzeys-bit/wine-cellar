import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rack.dart';

// ============================================================
// BOTTLE
// ============================================================
class Bottle {
  int? id;
  String name;
  String producer;
  int? vintage;
  String type;
  String drawer;
  int quantity;
  String? photoPath;
  String notes;
  String country;
  String region;
  String grapes;
  String alcohol;
  int? drinkFrom;
  int? drinkUntil;
  double? price;
  String pairing;
  String drinkWith;
  String description;

  Bottle({
    this.id,
    required this.name,
    this.producer = '',
    this.vintage,
    this.type = 'Red',
    required this.drawer,
    this.quantity = 1,
    this.photoPath,
    this.notes = '',
    this.country = '',
    this.region = '',
    this.grapes = '',
    this.alcohol = '',
    this.drinkFrom,
    this.drinkUntil,
    this.price,
    this.pairing = '',
    this.drinkWith = '',
    this.description = '',
  });

  String get category => categoryOf(type);

  String get title => vintage == null ? name : '$name $vintage';

  List<String> get grapeList => splitList(grapes);
  List<String> get peopleList => splitList(drinkWith);

  /// Text describing the drinking window, e.g. "2024–2030".
  String get drinkWindow {
    if (drinkFrom == null && drinkUntil == null) return '';
    if (drinkFrom != null && drinkUntil != null) return '$drinkFrom–$drinkUntil';
    if (drinkFrom != null) return 'from $drinkFrom';
    return 'until $drinkUntil';
  }

  /// 'now', 'wait' or 'past' compared to this year; '' if unknown.
  String get drinkStatus {
    final y = DateTime.now().year;
    if (drinkFrom == null && drinkUntil == null) return '';
    if (drinkUntil != null && drinkUntil! < y) return 'past';
    if (drinkFrom != null && drinkFrom! > y) return 'wait';
    return 'now';
  }

  bool drinkableIn(int year) {
    if (drinkFrom == null && drinkUntil == null) return false;
    if (drinkFrom != null && year < drinkFrom!) return false;
    if (drinkUntil != null && year > drinkUntil!) return false;
    return true;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'producer': producer,
        'vintage': vintage,
        'type': type,
        'drawer': drawer,
        'quantity': quantity,
        'photo_path': photoPath,
        'notes': notes,
        'country': country,
        'region': region,
        'grapes': grapes,
        'alcohol': alcohol,
        'drink_from': drinkFrom,
        'drink_until': drinkUntil,
        'price': price,
        'pairing': pairing,
        'drink_with': drinkWith,
        'description': description,
      };

  factory Bottle.fromMap(Map<String, Object?> m) => Bottle(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        producer: (m['producer'] as String?) ?? '',
        vintage: m['vintage'] as int?,
        type: (m['type'] as String?) ?? 'Red',
        drawer: (m['drawer'] as String?) ?? '',
        quantity: (m['quantity'] as int?) ?? 1,
        photoPath: m['photo_path'] as String?,
        notes: (m['notes'] as String?) ?? '',
        country: (m['country'] as String?) ?? '',
        region: (m['region'] as String?) ?? '',
        grapes: (m['grapes'] as String?) ?? '',
        alcohol: (m['alcohol'] as String?) ?? '',
        drinkFrom: m['drink_from'] as int?,
        drinkUntil: m['drink_until'] as int?,
        price: (m['price'] as num?)?.toDouble(),
        pairing: (m['pairing'] as String?) ?? '',
        drinkWith: (m['drink_with'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
      );
}

/// Splits "Merlot, Cabernet Franc / Malbec" into a clean list.
List<String> splitList(String s) => s
    .split(RegExp(r'[,;/]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

final NumberFormat _money =
    NumberFormat.currency(locale: 'nl_BE', symbol: '€', decimalDigits: 2);

String formatMoney(double v) => _money.format(v);

double? parseMoney(String s) {
  final t = s.replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

int totalCount(Iterable<Bottle> bottles) =>
    bottles.fold<int>(0, (s, b) => s + b.quantity);

double totalValue(Iterable<Bottle> bottles) =>
    bottles.fold<double>(0, (s, b) => s + (b.price ?? 0) * b.quantity);

/// Bottles per wine category (Red, White, Sparkling, Other).
Map<String, int> countByCategory(Iterable<Bottle> bottles) {
  final m = {for (final t in wineTypes) t: 0};
  for (final b in bottles) {
    m[b.category] = (m[b.category] ?? 0) + b.quantity;
  }
  return m;
}

// ============================================================
// DATABASE
// ============================================================
class CellarDb {
  static Database? _db;

  static const List<String> _v2Columns = [
    'country TEXT',
    'region TEXT',
    'grapes TEXT',
    'alcohol TEXT',
    'drink_from INTEGER',
    'drink_until INTEGER',
    'price REAL',
    'pairing TEXT',
    'drink_with TEXT',
    'description TEXT',
  ];

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'cellar.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bottles(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            producer TEXT,
            vintage INTEGER,
            type TEXT,
            drawer TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            photo_path TEXT,
            notes TEXT,
            added_at TEXT,
            ${_v2Columns.join(',\n            ')}
          )
        ''');
        await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final c in _v2Columns) {
            await db.execute('ALTER TABLE bottles ADD COLUMN $c');
          }
          await db.execute(
              'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)');
        }
      },
    );
    return _db!;
  }

  static Future<List<Bottle>> all() async {
    final d = await db;
    final rows = await d.query('bottles');
    final list = rows.map(Bottle.fromMap).toList();
    list.sort((a, b) {
      final c = drawerIndex(a.drawer).compareTo(drawerIndex(b.drawer));
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  static Future<void> save(Bottle b) async {
    final d = await db;
    final map = b.toMap();
    if (b.id == null) {
      map.remove('id');
      map['added_at'] = DateTime.now().toIso8601String();
      b.id = await d.insert('bottles', map);
    } else {
      await d.update('bottles', map, where: 'id = ?', whereArgs: [b.id]);
    }
  }

  static Future<void> delete(int id) async {
    final d = await db;
    await d.delete('bottles', where: 'id = ?', whereArgs: [id]);
  }

  /// Replaces every bottle with [bottles] in one go (used by restore).
  static Future<void> replaceAll(List<Bottle> bottles) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('bottles');
      final now = DateTime.now().toIso8601String();
      for (final b in bottles) {
        final map = b.toMap()..remove('id');
        map['added_at'] = now;
        b.id = await txn.insert('bottles', map);
      }
    });
  }

  static Future<String?> getSetting(String key) async {
    final d = await db;
    final rows =
        await d.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  static Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

// ============================================================
// +1 / -1
// ============================================================

/// Adds [delta] bottles (+1 or -1). When the last bottle is removed the
/// user is asked whether to delete the entry. Returns true if it changed.
Future<bool> changeQuantity(BuildContext context, Bottle b, int delta) async {
  if (delta > 0) {
    b.quantity += delta;
    await CellarDb.save(b);
    final all = await CellarDb.all();
    final used = all
        .where((x) => x.drawer == b.drawer)
        .fold<int>(0, (s, x) => s + x.quantity);
    if (used > capacityOf(b.drawer) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Drawer ${b.drawer} now holds $used bottles (room for ${capacityOf(b.drawer)})')));
    }
    return true;
  }
  if (b.quantity > 1) {
    b.quantity -= 1;
    await CellarDb.save(b);
    return true;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Last bottle'),
      content: Text('This was your last ${b.title}. Remove it from the cellar?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove')),
      ],
    ),
  );
  if (ok == true && b.id != null) {
    await CellarDb.delete(b.id!);
    return true;
  }
  return false;
}

// ============================================================
// SEARCH ON GOOGLE
// ============================================================
Future<void> searchOnGoogle(BuildContext context, Bottle b) async {
  final wine = [b.producer, b.name, b.vintage?.toString() ?? '']
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  final q = 'Give me all info on this wine: $wine. '
      'Put producer, year, grape, style (red, white, sparkling or other), '
      'pairing, when to drink and price in a simple table.';
  // udm=50 opens Google's AI Mode.
  final url = Uri.https('www.google.com', '/search', {'q': q, 'udm': '50'});
  bool ok = false;
  try {
    ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser')));
  }
}

// ============================================================
// CHOICES FOR THE DROPDOWNS
// ============================================================
const List<String> pairingOptions = [
  'Apero',
  'Fish',
  'Lamb',
  'Beef',
  'Game',
  'Poultry',
  'Spaghetti',
  'Cheese',
  'Dessert',
  'Other',
];

const List<String> wineCountries = [
  'Argentina', 'Armenia', 'Australia', 'Austria', 'Belgium',
  'Bosnia and Herzegovina', 'Brazil', 'Bulgaria', 'Canada', 'Chile', 'China',
  'Croatia', 'Cyprus', 'Czech Republic', 'England', 'France', 'Georgia',
  'Germany', 'Greece', 'Hungary', 'Israel', 'Italy', 'Japan', 'Lebanon',
  'Luxembourg', 'Mexico', 'Moldova', 'Montenegro', 'Morocco', 'Netherlands',
  'New Zealand', 'North Macedonia', 'Poland', 'Portugal', 'Romania', 'Serbia',
  'Slovakia', 'Slovenia', 'South Africa', 'Spain', 'Switzerland', 'Turkey',
  'Ukraine', 'United States', 'Uruguay',
];
