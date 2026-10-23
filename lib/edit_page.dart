import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data.dart';
import 'lookup.dart';
import 'rack.dart';
import 'settings_page.dart';
import 'widgets.dart';

// ============================================================
// ONE DRAWER (opened from the rack tab)
// ============================================================
class DrawerPage extends StatelessWidget {
  const DrawerPage({super.key, required this.code, this.highlight});

  final String code;
  final bool Function(Bottle)? highlight;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Drawer $code')),
      body: DrawerContents(code: code, onChanged: () {}, highlight: highlight),
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
  final Map<String, TextEditingController> _c = {};
  late String _type;
  String? _drawer;
  late int _qty;
  String? _photo;
  bool _looking = false;
  bool _loadingPhoto = false;
  bool _typeTouched = false;
  final Set<String> _auto = {};
  String? _lookupSummary;
  List<String> _knownPeople = [];

  bool get _isNew => widget.bottle == null;

  TextEditingController c(String key) => _c[key]!;

  @override
  void initState() {
    super.initState();
    final b = widget.bottle;
    String s(String? v) => v ?? '';
    final init = <String, String>{
      'name': s(b?.name),
      'producer': s(b?.producer),
      'vintage': b?.vintage?.toString() ?? '',
      'country': s(b?.country),
      'region': s(b?.region),
      'grapes': s(b?.grapes),
      'alcohol': s(b?.alcohol),
      'drinkFrom': b?.drinkFrom?.toString() ?? '',
      'drinkUntil': b?.drinkUntil?.toString() ?? '',
      'price': b?.price == null ? '' : b!.price!.toStringAsFixed(2),
      'pairing': s(b?.pairing),
      'drinkWith': s(b?.drinkWith),
      'description': s(b?.description),
      'notes': s(b?.notes),
    };
    init.forEach((k, v) => _c[k] = TextEditingController(text: v));
    _type = b == null ? 'Red' : categoryOf(b.type);
    _drawer = b?.drawer ?? widget.initialDrawer;
    _qty = b?.quantity ?? 1;
    _photo = b?.photoPath;
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    final all = await CellarDb.all();
    final m = <String, String>{};
    for (final b in all) {
      for (final p0 in b.peopleList) {
        m.putIfAbsent(p0.toLowerCase(), () => p0);
      }
    }
    if (!mounted) return;
    setState(() => _knownPeople = m.values.toList()..sort());
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- photo ----------------
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
      setState(() => _loadingPhoto = true);
      final x = await ImagePicker()
          .pickImage(source: src, maxWidth: 1200, imageQuality: 80);
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = p.join(
          dir.path, 'bottle_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(x.path).copy(dest);
      if (!mounted) return;
      setState(() => _photo = dest);
      // New bottle with a photo and nothing typed yet: look it up straight away.
      if (_isNew && c('name').text.trim().isEmpty) {
        final key = (await CellarDb.getSetting('gemini_key'))?.trim() ?? '';
        if (!mounted) return;
        if (key.isEmpty) {
          setState(() => _lookupSummary =
              'Tip: add a free Gemini key in ⚙️ Settings and the details are filled in '
              'automatically from the photo. For now, type them yourself or use the '
              'Google search button at the top.');
        } else {
          _lookup(auto: true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Could not get the photo: $e');
    } finally {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  // ---------------- online lookup ----------------
  Future<void> _lookup({bool auto = false}) async {
    final key = (await CellarDb.getSetting('gemini_key'))?.trim() ?? '';
    if (!mounted) return;
    if (key.isEmpty) {
      if (auto) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Set up online lookup'),
          content: const Text(
              'To look up wines online, add your free Gemini API key in Settings first.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open Settings')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SettingsPage()));
      }
      return;
    }
    final model = (await CellarDb.getSetting('gemini_model'))?.trim() ?? '';
    final useSearch = (await CellarDb.getSetting('gemini_search')) == '1';

    setState(() {
      _looking = true;
      _lookupSummary = null;
    });
    try {
      final info = await WineLookup.lookup(
        apiKey: key,
        model: model.isEmpty ? defaultModel : model,
        useGoogleSearch: useSearch,
        photoPath: _photo,
        name: c('name').text,
        producer: c('producer').text,
        vintage: c('vintage').text,
      );
      if (!mounted) return;

      final filled = <String>{};
      void fill(String field, String? value) {
        if (value == null || value.trim().isEmpty) return;
        if (c(field).text.trim().isNotEmpty) return; // never overwrite your data
        c(field).text = value.trim();
        filled.add(field);
      }

      fill('name', info.str('name'));
      fill('producer', info.str('producer'));
      fill('vintage', info.integer('vintage')?.toString());
      fill('country', info.str('country'));
      fill('region', info.str('region'));
      fill('grapes', info.str('grapes'));
      fill('alcohol', info.str('alcohol'));
      fill('drinkFrom', info.integer('drink_from')?.toString());
      fill('drinkUntil', info.integer('drink_until')?.toString());
      fill('price', info.number('price_eur')?.toStringAsFixed(2));
      fill('pairing', info.str('pairing'));
      fill('description', info.str('description'));

      final t = info.str('type');
      if (t != null && wineTypes.contains(t) && !_typeTouched && _isNew) {
        _type = t;
      }

      const labels = {
        'name': 'name',
        'producer': 'winemaker',
        'vintage': 'year',
        'country': 'country',
        'region': 'region',
        'grapes': 'grapes',
        'drinkFrom': 'drink from',
        'drinkUntil': 'drink until',
        'price': 'price',
        'pairing': 'pairing',
      };
      final missing = labels.entries
          .where((e) => c(e.key).text.trim().isEmpty)
          .map((e) => e.value)
          .toList();
      final conf = info.str('confidence');

      setState(() {
        _auto.addAll(filled);
        _lookupSummary = [
          filled.isEmpty
              ? 'Nothing new found online.'
              : 'Filled in ${filled.length} field${filled.length == 1 ? '' : 's'} (marked ✨). Please check them, especially price and drink window.',
          if (conf == 'low') 'Not sure this is the exact wine — double-check name and year.',
          if (missing.isNotEmpty) 'Still missing: ${missing.join(', ')}.',
          if (_drawer == null) 'Choose a drawer below.',
        ].join('\n');
      });
    } on LookupException catch (e) {
      if (mounted) setState(() => _lookupSummary = '⚠️ ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _lookupSummary = '⚠️ Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  // ---------------- drawer ----------------
  Future<void> _pickDrawer() async {
    final all = await CellarDb.all();
    final usage = <String, int>{};
    for (final b in all) {
      if (b.id != null && b.id == widget.bottle?.id) continue;
      usage[b.drawer] = (usage[b.drawer] ?? 0) + b.quantity;
    }
    if (!mounted) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          DrawerPickerSheet(usage: usage, selected: _drawer, needed: _qty),
    );
    if (code != null) setState(() => _drawer = code);
  }

  // ---------------- save / delete ----------------
  int? _year(String key, String label, List<String> errors) {
    final t = c(key).text.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v < 1800 || v > 2200) errors.add('$label should be a year, like 2028');
    return v;
  }

  Future<void> _save() async {
    final name = c('name').text.trim();
    if (name.isEmpty) {
      _snack('Please enter a name');
      return;
    }
    final drawer = _drawer;
    if (drawer == null) {
      _snack('Please choose a drawer');
      return;
    }
    final errors = <String>[];
    final vintage = _year('vintage', 'Year', errors);
    final from = _year('drinkFrom', 'Drink from', errors);
    final until = _year('drinkUntil', 'Drink until', errors);
    final priceText = c('price').text.trim();
    final price = parseMoney(priceText);
    if (priceText.isNotEmpty && price == null) errors.add('Price should be a number, like 24,50');
    if (errors.isNotEmpty) {
      _snack(errors.first);
      return;
    }

    final all = await CellarDb.all();
    final used = all
        .where((b) => b.drawer == drawer && b.id != widget.bottle?.id)
        .fold<int>(0, (s, b) => s + b.quantity);
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
      ..producer = c('producer').text.trim()
      ..vintage = vintage
      ..type = _type
      ..drawer = drawer
      ..quantity = _qty
      ..photoPath = _photo
      ..country = c('country').text.trim()
      ..region = c('region').text.trim()
      ..grapes = c('grapes').text.trim()
      ..alcohol = c('alcohol').text.trim()
      ..drinkFrom = from
      ..drinkUntil = until
      ..price = price
      ..pairing = c('pairing').text.trim()
      ..drinkWith = c('drinkWith').text.trim()
      ..description = c('description').text.trim()
      ..notes = c('notes').text.trim();
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
        content: Text('Remove ${b.title} from the cellar?'),
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

  // ---------------- UI ----------------
  Widget _field(String key, String label,
      {TextInputType? keyboard,
      int maxLines = 1,
      String? hint,
      String? prefix,
      bool words = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c(key),
        keyboardType: keyboard,
        maxLines: maxLines,
        textCapitalization:
            words ? TextCapitalization.words : TextCapitalization.sentences,
        onChanged: (_) => setState(() => _auto.remove(key)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefix,
          border: const OutlineInputBorder(),
          suffixIcon: _auto.contains(key)
              ? const Tooltip(
                  message: 'Found online',
                  child: Icon(Icons.auto_awesome, color: Colors.amber),
                )
              : null,
        ),
      ),
    );
  }

  /// Text field with a dropdown list of suggestions. You can pick one or type.
  Widget _dropdown(String key, String label, List<String> options,
      {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownMenu<String>(
        controller: c(key),
        label: Text(label),
        expandedInsets: EdgeInsets.zero,
        menuHeight: 320,
        enableFilter: true,
        requestFocusOnTap: true,
        keyboardType: keyboard,
        leadingIcon: _auto.contains(key)
            ? const Tooltip(
                message: 'Found online',
                child: Icon(Icons.auto_awesome, color: Colors.amber),
              )
            : null,
        onSelected: (_) {
          if (_auto.remove(key)) setState(() {});
        },
        dropdownMenuEntries: [
          for (final o in options) DropdownMenuEntry<String>(value: o, label: o),
        ],
      ),
    );
  }

  List<String> _years(int from, int to) =>
      [for (var y = from; from <= to ? y <= to : y >= to; from <= to ? y++ : y--) '$y'];

  void _togglePairing(String option) {
    final list = splitList(c('pairing').text);
    final i = list.indexWhere((x) => x.toLowerCase() == option.toLowerCase());
    if (i >= 0) {
      list.removeAt(i);
    } else {
      // Keep the categories first, specific dishes after.
      final cats = list
          .where((x) => pairingOptions.any((o) => o.toLowerCase() == x.toLowerCase()))
          .toList()
        ..add(option);
      final rest = list
          .where((x) => !pairingOptions.any((o) => o.toLowerCase() == x.toLowerCase()))
          .toList();
      cats.sort((a, b) => pairingOptions
          .indexWhere((o) => o.toLowerCase() == a.toLowerCase())
          .compareTo(pairingOptions.indexWhere((o) => o.toLowerCase() == b.toLowerCase())));
      list
        ..clear()
        ..addAll(cats)
        ..addAll(rest);
    }
    setState(() {
      _auto.remove('pairing');
      c('pairing').text = list.join(', ');
    });
  }

  Widget _row(List<Widget> children) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      );

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  void _addPerson(String person) {
    final list = splitList(c('drinkWith').text);
    if (list.any((x) => x.toLowerCase() == person.toLowerCase())) return;
    list.add(person);
    setState(() => c('drinkWith').text = list.join(', '));
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final hasPhoto = photo != null && photo.isNotEmpty && File(photo).existsSync();
    final year = DateTime.now().year;
    final pairingNow =
        splitList(c('pairing').text).map((e) => e.toLowerCase()).toSet();
    final peopleNow = splitList(c('drinkWith').text).map((e) => e.toLowerCase()).toSet();
    final suggestions =
        _knownPeople.where((x) => !peopleNow.contains(x.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add bottle' : 'Edit bottle'),
        actions: [
          IconButton(
            tooltip: 'Search on Google',
            icon: const Icon(Icons.travel_explore),
            onPressed: () {
              final name = c('name').text.trim();
              if (name.isEmpty) {
                _snack('Type the wine name first');
                return;
              }
              searchOnGoogle(
                context,
                Bottle(
                  name: name,
                  producer: c('producer').text.trim(),
                  vintage: int.tryParse(c('vintage').text.trim()),
                  drawer: '',
                ),
              );
            },
          ),
          if (!_isNew)
            IconButton(
              tooltip: 'Copy to another drawer',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => copyBottleToDrawer(context, widget.bottle!),
            ),
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: GestureDetector(
              onTap: _loadingPhoto ? null : _pickPhoto,
              child: _loadingPhoto
                  ? Container(
                      height: 160,
                      width: 160,
                      decoration: BoxDecoration(
                        color: Colors.brown.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Loading photo…'),
                        ],
                      ),
                    )
                  : hasPhoto
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(photo), height: 240),
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
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: _looking ? null : () => _lookup(),
              icon: _looking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.travel_explore),
              label: Text(_looking ? 'Looking it up…' : 'Look up online'),
            ),
          ),
          if (_lookupSummary != null)
            Card(
              color: Colors.amber.shade50,
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_lookupSummary!),
              ),
            ),
          const SizedBox(height: 16),
          _field('name', 'Wine name *'),
          _field('producer', 'Winemaker / château'),
          _row([
            _dropdown('vintage', 'Year', _years(year, 1950),
                keyboard: TextInputType.number),
            _field('alcohol', 'Alcohol', hint: '14%', words: false),
          ]),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in wineTypes)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: typeBackground(t), radius: 8),
                  label: Text(t),
                  selected: _type == t,
                  onSelected: (_) => setState(() {
                    _type = t;
                    _typeTouched = true;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _dropdown('country', 'Country', wineCountries),
          _field('region', 'Region'),
          _field('grapes', 'Grapes', hint: 'Malbec, Cabernet Franc'),

          _heading('In the cellar'),
          Card(
            margin: EdgeInsets.zero,
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
            margin: EdgeInsets.zero,
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
          _field('price', 'Price per bottle',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              prefix: '€ '),

          _heading('When to drink'),
          _row([
            _dropdown('drinkFrom', 'From (year)', _years(year - 10, year + 30),
                keyboard: TextInputType.number),
            _dropdown('drinkUntil', 'Until (year)', _years(year - 5, year + 50),
                keyboard: TextInputType.number),
          ]),

          _heading('Enjoying it'),
          Text('Pairs with', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final o in pairingOptions)
                FilterChip(
                  label: Text(o),
                  selected: pairingNow.contains(o.toLowerCase()),
                  onSelected: (_) => _togglePairing(o),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _field('pairing', 'Pairs with (you can also type dishes)',
              hint: 'Lamb, Cheese, dark chocolate', words: false),
          _field('drinkWith', 'Drink with', hint: 'Names, separated by commas'),
          if (suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final person in suggestions)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(person),
                      onPressed: () => _addPerson(person),
                    ),
                ],
              ),
            ),
          _field('description', 'About this wine', maxLines: 4, words: false),
          _field('notes', 'My notes', maxLines: 3, words: false),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
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
      {super.key,
      required this.usage,
      this.selected,
      required this.needed,
      this.title = 'Choose a drawer'});

  final Map<String, int> usage;
  final String? selected;
  final int needed;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
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
                                  style: Theme.of(context).textTheme.titleMedium),
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

// ============================================================
// COPY A BOTTLE TO ANOTHER DRAWER
// ============================================================

/// Lets the user pick a drawer and a number of bottles, then saves a copy
/// of [source] (same wine, photo and details) in that drawer.
Future<bool> copyBottleToDrawer(BuildContext context, Bottle source) async {
  final all = await CellarDb.all();
  final usage = <String, int>{};
  for (final b in all) {
    usage[b.drawer] = (usage[b.drawer] ?? 0) + b.quantity;
  }
  if (!context.mounted) return false;

  final drawer = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DrawerPickerSheet(
      usage: usage,
      needed: 1,
      title: 'Copy ${source.title} to…',
    ),
  );
  if (drawer == null || !context.mounted) return false;

  final free = capacityOf(drawer) - (usage[drawer] ?? 0);
  var qty = 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Copy to drawer $drawer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(free > 0
                ? 'Drawer $drawer has $free free spot${free == 1 ? '' : 's'}.'
                : 'Drawer $drawer is already full.'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: qty > 1 ? () => setD(() => qty--) : null,
                ),
                Text('$qty bottle${qty == 1 ? '' : 's'}',
                    style: Theme.of(ctx).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setD(() => qty++),
                ),
              ],
            ),
            if (qty > free)
              Text('That is more than fits in the drawer.',
                  style: TextStyle(color: Colors.red.shade700)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Copy')),
        ],
      ),
    ),
  );
  if (ok != true) return false;

  final copy = Bottle.fromMap(source.toMap())
    ..id = null
    ..drawer = drawer
    ..quantity = qty;
  await CellarDb.save(copy);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Copied $qty × ${source.title} to drawer $drawer')));
  }
  return true;
}
