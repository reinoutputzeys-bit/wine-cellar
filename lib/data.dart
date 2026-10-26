import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rack.dart';
import 'sync.dart';

// ============================================================
// BOTTLE
// ============================================================
// Where a wine "lives".
const String statusCellar = 'cellar';
const String statusWish = 'wish';
const String statusArchive = 'archive';

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

  /// statusCellar, statusWish or statusArchive.
  String status;

  /// Used to keep phones in sync (same wine entry on every phone).
  String? uuid;
  int? updatedAt;
  String? photoId;

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
    this.status = statusCellar,
    this.uuid,
    this.updatedAt,
    this.photoId,
  });

  bool get inCellar => status == statusCellar;

  /// Same wine = same winemaker + name + year (ignoring upper/lower case).
  String get wineKey => [
        producer.trim().toLowerCase(),
        name.trim().toLowerCase(),
        vintage?.toString() ?? '',
      ].join('|');

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
        'status': status,
        'uuid': uuid,
        'updated_at': updatedAt,
        'photo_id': photoId,
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
        status: (m['status'] as String?) ?? statusCellar,
        uuid: m['uuid'] as String?,
        updatedAt: m['updated_at'] as int?,
        photoId: m['photo_id'] as String?,
      );

  /// Fills empty fields of this wine with data from [other] and joins notes.
  void absorb(Bottle other) {
    String pick(String mine, String theirs) => mine.trim().isEmpty ? theirs : mine;
    producer = pick(producer, other.producer);
    country = pick(country, other.country);
    region = pick(region, other.region);
    grapes = pick(grapes, other.grapes);
    alcohol = pick(alcohol, other.alcohol);
    pairing = pick(pairing, other.pairing);
    description = pick(description, other.description);
    vintage ??= other.vintage;
    drinkFrom ??= other.drinkFrom;
    drinkUntil ??= other.drinkUntil;
    price ??= other.price;
    if (photoPath == null || photoPath!.isEmpty) photoPath = other.photoPath;
    final people = {...peopleList};
    for (final x in other.peopleList) {
      if (!people.any((y) => y.toLowerCase() == x.toLowerCase())) people.add(x);
    }
    drinkWith = people.join(', ');
    final n1 = notes.trim(), n2 = other.notes.trim();
    if (n1.isEmpty) {
      notes = n2;
    } else if (n2.isNotEmpty && !n1.contains(n2)) {
      notes = '$n1\n$n2';
    }
  }
}

final math.Random _rnd = math.Random.secure();

/// A random id that is unique across phones.
String newUuid() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
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

/// Wines per category, counting each entry once (wishlist / archive).
Map<String, int> countEntriesByCategory(Iterable<Bottle> bottles) {
  final m = {for (final t in wineTypes) t: 0};
  for (final b in bottles) {
    m[b.category] = (m[b.category] ?? 0) + 1;
  }
  return m;
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
      version: 4,
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
            ${_v2Columns.join(',\n            ')},
            status TEXT DEFAULT 'cellar',
            uuid TEXT,
            updated_at INTEGER,
            dirty INTEGER DEFAULT 1,
            photo_id TEXT
          )
        ''');
        await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
        await db.execute(
            'CREATE TABLE pending_deletes(uuid TEXT PRIMARY KEY, deleted_at INTEGER)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final c in _v2Columns) {
            await db.execute('ALTER TABLE bottles ADD COLUMN $c');
          }
          await db.execute(
              'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)');
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE bottles ADD COLUMN status TEXT DEFAULT 'cellar'");
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE bottles ADD COLUMN uuid TEXT');
          await db.execute('ALTER TABLE bottles ADD COLUMN updated_at INTEGER');
          await db.execute('ALTER TABLE bottles ADD COLUMN dirty INTEGER DEFAULT 1');
          await db.execute('ALTER TABLE bottles ADD COLUMN photo_id TEXT');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS pending_deletes(uuid TEXT PRIMARY KEY, deleted_at INTEGER)');
          final now = DateTime.now().millisecondsSinceEpoch;
          final rows = await db.query('bottles', columns: ['id']);
          for (final r in rows) {
            await db.update(
                'bottles', {'uuid': newUuid(), 'updated_at': now, 'dirty': 1},
                where: 'id = ?', whereArgs: [r['id']]);
          }
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

  /// Saves a change made on this phone; it is sent to the shared cellar.
  static Future<void> save(Bottle b) async {
    final d = await db;
    b.uuid ??= newUuid();
    b.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (b.id != null) {
      // A new photo needs to be uploaded again.
      final old = await d.query('bottles',
          columns: ['photo_path', 'photo_id'], where: 'id = ?', whereArgs: [b.id]);
      if (old.isNotEmpty) {
        final oldPath = old.first['photo_path'] as String?;
        final oldId = old.first['photo_id'] as String?;
        if (b.photoPath == null && oldPath != null && b.photoId != null && b.photoId == oldId) {
          // The photo arrived from the other phone after this screen was opened.
          b.photoPath = oldPath;
        } else if (oldPath != b.photoPath) {
          b.photoId = null;
        }
      }
    }
    final map = b.toMap()..['dirty'] = 1;
    if (b.id == null) {
      map.remove('id');
      map['added_at'] = DateTime.now().toIso8601String();
      b.id = await d.insert('bottles', map);
    } else {
      await d.update('bottles', map, where: 'id = ?', whereArgs: [b.id]);
    }
    Sync.instance.requestSync();
  }

  static Future<void> delete(int id) async {
    final d = await db;
    final rows = await d.query('bottles',
        columns: ['uuid'], where: 'id = ?', whereArgs: [id]);
    await d.delete('bottles', where: 'id = ?', whereArgs: [id]);
    final uuid = rows.isEmpty ? null : rows.first['uuid'] as String?;
    if (uuid != null) {
      await d.insert(
          'pending_deletes',
          {'uuid': uuid, 'deleted_at': DateTime.now().millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    Sync.instance.requestSync();
  }

  /// Replaces every bottle with [bottles] in one go (used by restore).
  static Future<void> replaceAll(List<Bottle> bottles) async {
    final d = await db;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await d.transaction((txn) async {
      final old = await txn.query('bottles', columns: ['uuid']);
      final keep = bottles.map((b) => b.uuid).whereType<String>().toSet();
      for (final r in old) {
        final u = r['uuid'] as String?;
        if (u != null && !keep.contains(u)) {
          await txn.insert('pending_deletes', {'uuid': u, 'deleted_at': nowMs},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await txn.delete('bottles');
      final now = DateTime.now().toIso8601String();
      for (final b in bottles) {
        b
          ..uuid ??= newUuid()
          ..updatedAt = nowMs
          ..photoId = null;
        final map = b.toMap()
          ..remove('id')
          ..['dirty'] = 1;
        map['added_at'] = now;
        b.id = await txn.insert('bottles', map);
      }
    });
    Sync.instance.requestSync();
  }

  // ---------------- used by the sync ----------------
  static Future<List<Map<String, Object?>>> dirtyRows() async {
    final d = await db;
    return d.query('bottles', where: 'dirty = 1');
  }

  static Future<Map<String, Object?>?> rowByUuid(String uuid) async {
    final d = await db;
    final rows = await d.query('bottles', where: 'uuid = ?', whereArgs: [uuid]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Marks a row as sent, unless it was changed again in the meantime.
  static Future<void> markClean(String uuid, int? updatedAt, String? photoId) async {
    final d = await db;
    await d.update('bottles', {'dirty': 0, 'photo_id': photoId},
        where: 'uuid = ? AND updated_at = ?', whereArgs: [uuid, updatedAt]);
  }

  static Future<void> setPhotoId(String uuid, String photoId) async {
    final d = await db;
    await d.update('bottles', {'photo_id': photoId},
        where: 'uuid = ?', whereArgs: [uuid]);
  }

  static Future<List<String>> pendingDeletes() async {
    final d = await db;
    final rows = await d.query('pending_deletes');
    return rows.map((r) => r['uuid'] as String).toList();
  }

  static Future<void> clearPendingDelete(String uuid) async {
    final d = await db;
    await d.delete('pending_deletes', where: 'uuid = ?', whereArgs: [uuid]);
  }

  /// Writes a row that came from the other phone (not sent back).
  static Future<void> putFromRemote(Map<String, Object?> row) async {
    final d = await db;
    final uuid = row['uuid'] as String;
    final map = Map<String, Object?>.from(row)
      ..remove('id')
      ..['dirty'] = 0;
    final n = await d.update('bottles', map, where: 'uuid = ?', whereArgs: [uuid]);
    if (n == 0) await d.insert('bottles', map);
  }

  static Future<void> deleteFromRemote(String uuid) async {
    final d = await db;
    await d.delete('bottles', where: 'uuid = ?', whereArgs: [uuid]);
  }

  static Future<List<Map<String, Object?>>> rowsWithPhotoId() async {
    final d = await db;
    return d.query('bottles', where: 'photo_id IS NOT NULL');
  }

  static Future<void> setPhotoPath(String uuid, String path) async {
    final d = await db;
    await d.update('bottles', {'photo_path': path},
        where: 'uuid = ?', whereArgs: [uuid]);
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
  return finishBottle(context, b);
}

/// The last bottle of an entry is gone. Its data is kept in the archive
/// (unless the same wine still lies in another drawer).
/// Returns true if something changed.
Future<bool> finishBottle(BuildContext context, Bottle b) async {
  final all = await CellarDb.all();
  final elsewhere = all
      .where((x) => x.inCellar && x.id != b.id && x.wineKey == b.wineKey)
      .toList();
  if (!context.mounted) return false;

  if (elsewhere.isNotEmpty) {
    final where = elsewhere.map((x) => x.drawer).toSet().join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last bottle in this drawer'),
        content: Text(
            '${b.title} is gone from drawer ${b.drawer}. You still have it in drawer $where, '
            'so its details stay there.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove from drawer')),
        ],
      ),
    );
    if (ok != true || b.id == null) return false;
    await CellarDb.delete(b.id!);
    return true;
  }

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Last bottle'),
      content: Text('This was your last ${b.title}.\n\n'
          'Move it to the archive? All details and your notes are kept, '
          'so you can put it back in the cellar later.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Delete completely')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 'archive'),
            child: const Text('Archive')),
      ],
    ),
  );
  if (b.id == null) return false;
  if (choice == 'delete') {
    await CellarDb.delete(b.id!);
    return true;
  }
  if (choice == 'archive') {
    await archiveBottle(b);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${b.title} moved to the archive')));
    }
    return true;
  }
  return false;
}

/// Moves [b] to the archive. If the archive already has this wine, the two
/// are merged into one entry (no duplicates).
Future<void> archiveBottle(Bottle b) async {
  final all = await CellarDb.all();
  final existing = all
      .where((x) => x.status == statusArchive && x.id != b.id && x.wineKey == b.wineKey)
      .toList();
  if (existing.isNotEmpty) {
    final keep = existing.first;
    // The bottle just finished has the newest data; old entry fills the gaps.
    b.absorb(keep);
    b
      ..status = statusArchive
      ..drawer = ''
      ..quantity = 0;
    await CellarDb.save(b);
    for (final x in existing) {
      if (x.id != null) await CellarDb.delete(x.id!);
    }
    return;
  }
  b
    ..status = statusArchive
    ..drawer = ''
    ..quantity = 0;
  await CellarDb.save(b);
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
