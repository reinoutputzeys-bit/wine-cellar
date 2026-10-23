import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ============================================================
// RACK LAYOUT
// Columns in physical order, left to right.
// Each number is the max bottles for that drawer, top drawer first.
// ============================================================
const Map<String, List<int>> rackColumns = {
  'A': [6, 6, 6, 6, 6, 6, 6, 6],
  'B': [6, 6, 3, 3, 3, 3, 3],
  'C': [6, 6, 6, 6, 6, 6],
  'D': [6, 6, 6, 6, 6, 12, 12],
  'E': [6, 6, 6, 6, 6],
  'F': [6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
  'G': [6, 6, 6, 6, 6, 6],
};

/// The rack turns the corner of the L after these columns.
const Set<String> cornerAfter = {'B'};

final List<String> allDrawerCodes = [
  for (final e in rackColumns.entries)
    for (var i = 0; i < e.value.length; i++) '${e.key}${i + 1}',
];

int capacityOf(String code) {
  if (code.length < 2) return 0;
  final col = rackColumns[code.substring(0, 1)];
  final i = int.tryParse(code.substring(1)) ?? 0;
  if (col == null || i < 1 || i > col.length) return 0;
  return col[i - 1];
}

int get totalCapacity =>
    rackColumns.values.expand((c) => c).fold(0, (a, b) => a + b);

Map<String, int> usageOf(List<Bottle> bottles, {int? excludeId}) {
  final m = <String, int>{};
  for (final b in bottles) {
    if (excludeId != null && b.id == excludeId) continue;
    m[b.drawer] = (m[b.drawer] ?? 0) + b.quantity;
  }
  return m;
}

const List<String> wineTypes = [
  'Red',
  'White',
  'Rosé',
  'Sparkling',
  'Sweet',
  'Other',
];

Color typeColor(String t) {
  switch (t) {
    case 'Red':
      return const Color(0xFF8E1B2C);
    case 'White':
      return const Color(0xFFC9B458);
    case 'Rosé':
      return const Color(0xFFE08A9B);
    case 'Sparkling':
      return const Color(0xFF7FB1C9);
    case 'Sweet':
      return const Color(0xFFC8862A);
    default:
      return Colors.grey;
  }
}

// ============================================================
// DATA
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
  });

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
      );
}

class CellarDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'cellar.db'),
      version: 1,
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
            added_at TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<List<Bottle>> all() async {
    final d = await db;
    final rows = await d.query('bottles');
    final list = rows.map(Bottle.fromMap).toList();
    list.sort((a, b) {
      final c = allDrawerCodes
          .indexOf(a.drawer)
          .compareTo(allDrawerCodes.indexOf(b.drawer));
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
}

/// Takes one bottle out. Returns true if the whole entry was removed.
Future<bool> drinkOne(BuildContext context, Bottle b) async {
  if (b.quantity > 1) {
    b.quantity -= 1;
    await CellarDb.save(b);
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Last bottle'),
      content: Text('This was your last ${b.name}. Remove it from the cellar?'),
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
// APP
// ============================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WineCellarApp());
}

class WineCellarApp extends StatelessWidget {
  const WineCellarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wine Cellar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5D4037)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  List<Bottle> _bottles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await CellarDb.all();
    if (!mounted) return;
    setState(() {
      _bottles = b;
      _loading = false;
    });
  }

  Future<void> _openDrawer(String code) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => DrawerPage(code: code)));
    _load();
  }

  Future<void> _openBottle(Bottle? b) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => BottleEditPage(bottle: b)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _bottles.fold<int>(0, (s, b) => s + b.quantity);
    final pages = [
      RackView(bottles: _bottles, onOpenDrawer: _openDrawer),
      BottleListView(bottles: _bottles, onOpen: _openBottle),
      const RackPhotoView(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wine Cellar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('$total / $totalCapacity bottles')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pages[_tab],
      floatingActionButton: _tab == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openBottle(null),
              icon: const Icon(Icons.add),
              label: const Text('Add bottle'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Rack'),
          NavigationDestination(icon: Icon(Icons.wine_bar), label: 'Bottles'),
          NavigationDestination(icon: Icon(Icons.photo), label: 'Photo'),
        ],
      ),
    );
  }
}

// ============================================================
// RACK MAP
// ============================================================
class RackView extends StatelessWidget {
  const RackView({super.key, required this.bottles, required this.onOpenDrawer});

  final List<Bottle> bottles;
  final void Function(String code) onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final usage = usageOf(bottles);
    final children = <Widget>[];
    for (final e in rackColumns.entries) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Text(e.key, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            for (var i = 0; i < e.value.length; i++)
              DrawerTile(
                code: '${e.key}${i + 1}',
                used: usage['${e.key}${i + 1}'] ?? 0,
                capacity: e.value[i],
                onTap: () => onOpenDrawer('${e.key}${i + 1}'),
              ),
          ],
        ),
      ));
      if (cornerAfter.contains(e.key)) {
        children.add(Container(
          width: 4,
          height: 420,
          margin: const EdgeInsets.only(left: 8, right: 8, top: 36),
          decoration: BoxDecoration(
            color: Colors.brown.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ));
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class DrawerTile extends StatelessWidget {
  const DrawerTile({
    super.key,
    required this.code,
    required this.used,
    required this.capacity,
    required this.onTap,
  });

  final String code;
  final int used;
  final int capacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final over = used > capacity;
    final fill = capacity == 0 ? 0.0 : (used / capacity).clamp(0.0, 1.0);
    final Color bg = used == 0
        ? Colors.brown.shade50
        : over
            ? Colors.red.shade300
            : Color.lerp(
                const Color(0xFFE9D7C4), const Color(0xFF8D5A3B), fill)!;
    final Color fg = (fill > 0.6 || over) ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: capacity >= 12 ? 64 : 46,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(code,
                    style: TextStyle(fontWeight: FontWeight.bold, color: fg)),
                Text('$used/$capacity',
                    style: TextStyle(fontSize: 12, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTTLE LIST + SEARCH
// ============================================================
class BottleListView extends StatefulWidget {
  const BottleListView({super.key, required this.bottles, required this.onOpen});

  final List<Bottle> bottles;
  final void Function(Bottle) onOpen;

  @override
  State<BottleListView> createState() => _BottleListViewState();
}

class _BottleListViewState extends State<BottleListView> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase().trim();
    final list = widget.bottles
        .where((b) =>
            q.isEmpty ||
            '${b.name} ${b.producer} ${b.vintage ?? ''} ${b.drawer} ${b.type}'
                .toLowerCase()
                .contains(q))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name, producer, year, drawer…',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(widget.bottles.isEmpty
                      ? 'No bottles yet. Tap “Add bottle” to start.'
                      : 'Nothing matches your search'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  itemBuilder: (_, i) => BottleTile(
                    bottle: list[i],
                    onTap: () => widget.onOpen(list[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class BottleTile extends StatelessWidget {
  const BottleTile(
      {super.key, required this.bottle, required this.onTap, this.trailing});

  final Bottle bottle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final b = bottle;
    return ListTile(
      onTap: onTap,
      leading: BottleThumb(photoPath: b.photoPath, type: b.type),
      title: Text(b.vintage == null ? b.name : '${b.name} ${b.vintage}'),
      subtitle: Text([
        if (b.producer.isNotEmpty) b.producer,
        b.type,
        'Drawer ${b.drawer}',
      ].join(' · ')),
      trailing: trailing ??
          Text('×${b.quantity}',
              style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class BottleThumb extends StatelessWidget {
  const BottleThumb(
      {super.key, this.photoPath, required this.type, this.size = 48});

  final String? photoPath;
  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: typeColor(type),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.wine_bar, color: Colors.white),
    );
  }
}

// ============================================================
// RACK PHOTO (panorama, pinch to zoom)
// ============================================================
class RackPhotoView extends StatelessWidget {
  const RackPhotoView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => InteractiveViewer(
        constrained: false,
        minScale: 0.3,
        maxScale: 5,
        child: Image.asset(
          'assets/cellar/rack.jpg',
          height: c.maxHeight,
          fit: BoxFit.fitHeight,
          errorBuilder: (context, error, stack) => SizedBox(
            width: c.maxWidth,
            height: c.maxHeight,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Upload rack.jpg to the assets/cellar/ folder in the repo to see your rack here.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ONE DRAWER
// ============================================================
class DrawerPage extends StatefulWidget {
  const DrawerPage({super.key, required this.code});

  final String code;

  @override
  State<DrawerPage> createState() => _DrawerPageState();
}

class _DrawerPageState extends State<DrawerPage> {
  List<Bottle> _bottles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await CellarDb.all();
    if (!mounted) return;
    setState(
        () => _bottles = all.where((b) => b.drawer == widget.code).toList());
  }

  Future<void> _edit(Bottle? b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              BottleEditPage(bottle: b, initialDrawer: widget.code)),
    );
    _load();
  }

  Future<void> _drink(Bottle b) async {
    await drinkOne(context, b);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cap = capacityOf(widget.code);
    final used = _bottles.fold<int>(0, (s, b) => s + b.quantity);
    return Scaffold(
      appBar: AppBar(title: Text('Drawer ${widget.code}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add here'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$used of $cap spots used',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: cap == 0 ? 0 : (used / cap).clamp(0.0, 1.0),
                  minHeight: 8,
                ),
              ],
            ),
          ),
          Expanded(
            child: _bottles.isEmpty
                ? const Center(child: Text('This drawer is empty'))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final b in _bottles)
                        BottleTile(
                          bottle: b,
                          onTap: () => _edit(b),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('×${b.quantity}'),
                              IconButton(
                                tooltip: 'Drink one',
                                icon: const Icon(Icons.local_bar),
                                onPressed: () => _drink(b),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ADD / EDIT BOTTLE
// ============================================================
class BottleEditPage extends StatefulWidget {
  const BottleEditPage({super.key, this.bottle, this.initialDrawer});

  final Bottle? bottle;
  final String? initialDrawer;

  @override
  State<BottleEditPage> createState() => _BottleEditPageState();
}

class _BottleEditPageState extends State<BottleEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _producer;
  late final TextEditingController _vintage;
  late final TextEditingController _notes;
  late String _type;
  String? _drawer;
  late int _qty;
  String? _photo;

  bool get _isNew => widget.bottle == null;

  @override
  void initState() {
    super.initState();
    final b = widget.bottle;
    _name = TextEditingController(text: b?.name ?? '');
    _producer = TextEditingController(text: b?.producer ?? '');
    _vintage = TextEditingController(text: b?.vintage?.toString() ?? '');
    _notes = TextEditingController(text: b?.notes ?? '');
    _type = b?.type ?? 'Red';
    _drawer = b?.drawer ?? widget.initialDrawer;
    _qty = b?.quantity ?? 1;
    _photo = b?.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _producer.dispose();
    _vintage.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;
    try {
      final x = await ImagePicker()
          .pickImage(source: src, maxWidth: 1200, imageQuality: 80);
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = p.join(
          dir.path, 'bottle_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(x.path).copy(dest);
      if (!mounted) return;
      setState(() => _photo = dest);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not get the photo: $e');
    }
  }

  Future<void> _pickDrawer() async {
    final all = await CellarDb.all();
    final usage = usageOf(all, excludeId: widget.bottle?.id);
    if (!mounted) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          DrawerPickerSheet(usage: usage, selected: _drawer, needed: _qty),
    );
    if (code != null) setState(() => _drawer = code);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Please enter a name');
      return;
    }
    final drawer = _drawer;
    if (drawer == null) {
      _snack('Please choose a drawer');
      return;
    }
    final vintageText = _vintage.text.trim();
    final vintage = vintageText.isEmpty ? null : int.tryParse(vintageText);
    if (vintageText.isNotEmpty && vintage == null) {
      _snack('Vintage should be a year, like 2016');
      return;
    }

    final all = await CellarDb.all();
    final used = usageOf(all, excludeId: widget.bottle?.id)[drawer] ?? 0;
    final free = capacityOf(drawer) - used;
    if (_qty > free) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Drawer is full'),
          content: Text(
              'Drawer $drawer has only ${free < 0 ? 0 : free} free spot(s). Save anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }

    final b = widget.bottle ?? Bottle(name: name, drawer: drawer);
    b
      ..name = name
      ..producer = _producer.text.trim()
      ..vintage = vintage
      ..type = _type
      ..drawer = drawer
      ..quantity = _qty
      ..photoPath = _photo
      ..notes = _notes.text.trim();
    await CellarDb.save(b);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final b = widget.bottle;
    if (b == null || b.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete bottle?'),
        content: Text('Remove ${b.name} from the cellar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await CellarDb.delete(b.id!);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _drink() async {
    final b = widget.bottle;
    if (b == null) return;
    final removed = await drinkOne(context, b);
    if (!mounted) return;
    if (removed) {
      Navigator.pop(context);
    } else {
      setState(() => _qty = b.quantity);
      _snack('Cheers! ${b.quantity} left');
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final hasPhoto = photo != null && File(photo).existsSync();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add bottle' : 'Edit bottle'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: hasPhoto
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(photo!), height: 240),
                    )
                  : Container(
                      height: 160,
                      width: 160,
                      decoration: BoxDecoration(
                        color: Colors.brown.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 40),
                          SizedBox(height: 8),
                          Text('Add photo'),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Wine name *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _producer,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Producer / château', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vintage,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Vintage (year)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in wineTypes)
                ChoiceChip(
                  label: Text(t),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.grid_view),
              title: Text(_drawer == null ? 'Choose drawer *' : 'Drawer $_drawer'),
              subtitle: _drawer == null
                  ? null
                  : Text('Holds ${capacityOf(_drawer!)} bottles'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDrawer,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.wine_bar),
              title: const Text('Number of bottles'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  ),
                  Text('$_qty', style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => setState(() => _qty++),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Notes (tasting, drink by, price…)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _drink,
              icon: const Icon(Icons.local_bar),
              label: const Text('Drink one'),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// DRAWER PICKER
// ============================================================
class DrawerPickerSheet extends StatelessWidget {
  const DrawerPickerSheet(
      {super.key, required this.usage, this.selected, required this.needed});

  final Map<String, int> usage;
  final String? selected;
  final int needed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Choose a drawer',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in rackColumns.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              Text(e.key,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              for (var i = 0; i < e.value.length; i++)
                                _tile(context, '${e.key}${i + 1}', e.value[i]),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String code, int cap) {
    final free = cap - (usage[code] ?? 0);
    final fits = free >= needed;
    final isSel = code == selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isSel
            ? Theme.of(context).colorScheme.primary
            : fits
                ? Colors.green.shade100
                : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => Navigator.pop(context, code),
          child: SizedBox(
            width: 64,
            height: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(code,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSel ? Colors.white : Colors.black87)),
                Text('${free < 0 ? 0 : free} free',
                    style: TextStyle(
                        fontSize: 11,
                        color: isSel ? Colors.white : Colors.black54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
