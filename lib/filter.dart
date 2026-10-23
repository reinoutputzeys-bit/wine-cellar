import 'package:flutter/material.dart';

import 'data.dart';
import 'rack.dart';

String _norm(String s) => s.trim().toLowerCase();

// ============================================================
// FILTER STATE
// Each group holds the selected values; a bottle must match at least
// one value in every group that has a selection.
// ============================================================
class BottleFilter {
  static const List<String> keys = [
    'type',
    'drink',
    'vintage',
    'country',
    'grape',
    'producer',
    'people',
    'pairing',
    'column',
    'drawer',
  ];

  static const Map<String, String> groupTitles = {
    'type': 'Type',
    'drink': 'When to drink',
    'vintage': 'Year',
    'country': 'Country',
    'grape': 'Grape',
    'producer': 'Winemaker',
    'people': 'Drink with',
    'pairing': 'Pairs with',
    'column': 'Column',
    'drawer': 'Drawer',
  };

  BottleFilter([Map<String, Set<String>>? from, this.text = ''])
      : groups = {for (final k in keys) k: {...?from?[k]}};

  final Map<String, Set<String>> groups;
  String text;

  BottleFilter copy() => BottleFilter(groups, text);

  Set<String> operator [](String key) => groups[key]!;

  int get count => groups.values.fold(0, (a, s) => a + s.length);

  bool get isActive => count > 0 || text.trim().isNotEmpty;

  BottleFilter toggled(String key, String value) {
    final c = copy();
    if (!c[key].remove(value)) c[key].add(value);
    return c;
  }

  BottleFilter cleared() => BottleFilter(null, text);

  bool drawerAllowed(String code) {
    final cols = this['column'];
    final drs = this['drawer'];
    if (cols.isEmpty && drs.isEmpty) return true;
    return cols.contains(columnOf(code)) || drs.contains(code);
  }

  /// True if the filter limits which drawers are shown.
  bool get limitsDrawers => this['column'].isNotEmpty || this['drawer'].isNotEmpty;

  /// True if anything other than column/drawer is selected.
  bool get limitsWines =>
      text.trim().isNotEmpty ||
      keys.any((k) => k != 'column' && k != 'drawer' && this[k].isNotEmpty);

  bool matches(Bottle b) {
    if (!drawerAllowed(b.drawer)) return false;

    bool anyIn(String key, Iterable<String> values) {
      final sel = this[key];
      if (sel.isEmpty) return true;
      final vals = values.map(_norm).toSet();
      return sel.any((s) => vals.contains(_norm(s)));
    }

    if (!anyIn('type', [b.category])) return false;
    if (!anyIn('vintage', [b.vintage?.toString() ?? ''])) return false;
    if (!anyIn('country', [b.country])) return false;
    if (!anyIn('grape', b.grapeList)) return false;
    if (!anyIn('producer', [b.producer])) return false;
    if (!anyIn('people', b.peopleList)) return false;
    if (!anyIn('pairing', splitList(b.pairing))) return false;

    final drink = this['drink'];
    if (drink.isNotEmpty) {
      final ok = drink.any((d) {
        if (d.startsWith('y')) {
          final y = int.tryParse(d.substring(1));
          return y != null && b.drinkableIn(y);
        }
        return b.drinkStatus == d;
      });
      if (!ok) return false;
    }

    final t = _norm(text);
    if (t.isNotEmpty) {
      final hay = [
        b.name,
        b.producer,
        b.vintage?.toString() ?? '',
        b.drawer,
        b.type,
        b.country,
        b.region,
        b.grapes,
        b.pairing,
        b.drinkWith,
        b.notes,
      ].join(' ').toLowerCase();
      if (!hay.contains(t)) return false;
    }
    return true;
  }

  List<Bottle> apply(List<Bottle> bottles) => bottles.where(matches).toList();

  static String label(String key, String value) {
    switch (key) {
      case 'drink':
        if (value == 'now') return 'Ready now';
        if (value == 'wait') return 'Not ready yet';
        if (value == 'past') return 'Past its best';
        return 'Drink in ${value.substring(1)}';
      case 'people':
        return 'With $value';
      case 'column':
        return 'Column $value';
      case 'drawer':
        return 'Drawer $value';
      default:
        return value;
    }
  }
}

// ============================================================
// FILTER BAR (button + active chips)
// ============================================================
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.filter,
    required this.bottles,
    required this.onChanged,
    this.showSearch = false,
  });

  final BottleFilter filter;
  final List<Bottle> bottles;
  final ValueChanged<BottleFilter> onChanged;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final k in BottleFilter.keys) {
      for (final v in filter[k]) {
        chips.add(Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text(BottleFilter.label(k, v)),
            onDeleted: () => onChanged(filter.toggled(k, v)),
            visualDensity: VisualDensity.compact,
          ),
        ));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _SearchField(
              text: filter.text,
              onChanged: (t) {
                final c = filter.copy();
                c.text = t;
                onChanged(c);
              },
            ),
          ),
        SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Badge(
                isLabelVisible: filter.count > 0,
                label: Text('${filter.count}'),
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      openFilterSheet(context, filter, bottles, onChanged),
                  icon: const Icon(Icons.tune),
                  label: const Text('Filter'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ...chips,
                    if (chips.isNotEmpty)
                      TextButton(
                        onPressed: () => onChanged(filter.cleared()),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.text, required this.onChanged});

  final String text;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.text);

  @override
  void didUpdateWidget(covariant _SearchField old) {
    super.didUpdateWidget(old);
    if (widget.text != _c.text) _c.text = widget.text;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Search name, producer, people, notes…',
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _c.clear();
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

// ============================================================
// FILTER SHEET
// ============================================================
Future<void> openFilterSheet(BuildContext context, BottleFilter filter,
    List<Bottle> bottles, ValueChanged<BottleFilter> onChanged) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => FilterSheet(
        initial: filter,
        bottles: bottles,
        onChanged: onChanged,
        scrollController: scroll,
      ),
    ),
  );
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.initial,
    required this.bottles,
    required this.onChanged,
    required this.scrollController,
  });

  final BottleFilter initial;
  final List<Bottle> bottles;
  final ValueChanged<BottleFilter> onChanged;
  final ScrollController scrollController;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late BottleFilter _f = widget.initial.copy();

  void _set(BottleFilter f) {
    setState(() => _f = f);
    widget.onChanged(f);
  }

  /// Distinct values (case-insensitive) with bottle counts.
  Map<String, int> _options(Iterable<String> Function(Bottle) pick) {
    final display = <String, String>{};
    final counts = <String, int>{};
    for (final b in widget.bottles) {
      for (final v in pick(b)) {
        final t = v.trim();
        if (t.isEmpty) continue;
        final k = t.toLowerCase();
        display.putIfAbsent(k, () => t);
        counts[k] = (counts[k] ?? 0) + b.quantity;
      }
    }
    final keys = counts.keys.toList()..sort();
    return {for (final k in keys) display[k]!: counts[k]!};
  }

  Widget _section(String key, Map<String, int> options,
      {Map<String, String>? labels, Widget Function(String)? avatar}) {
    final selected = _f[key];
    // Keep selected values visible even if no bottle has them any more.
    final all = {...options};
    for (final s in selected) {
      if (!all.keys.any((k) => _norm(k) == _norm(s))) all[s] = 0;
    }
    if (all.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(BottleFilter.groupTitles[key]!,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final e in all.entries)
                FilterChip(
                  avatar: avatar?.call(e.key),
                  label: Text(
                      '${labels?[e.key] ?? e.key}${e.value > 0 ? '  ${e.value}' : ''}'),
                  selected: selected.any((s) => _norm(s) == _norm(e.key)),
                  onSelected: (_) {
                    final existing = selected.firstWhere(
                        (s) => _norm(s) == _norm(e.key),
                        orElse: () => e.key);
                    _set(_f.toggled(key, existing));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottles = widget.bottles;
    final now = DateTime.now().year;

    final types = {
      for (final t in wineTypes)
        t: bottles.where((b) => b.category == t).fold<int>(0, (s, b) => s + b.quantity)
    };

    // When to drink
    final drink = <String, int>{};
    final drinkLabels = <String, String>{};
    for (final s in ['now', 'wait', 'past']) {
      final n = bottles
          .where((b) => b.drinkStatus == s)
          .fold<int>(0, (a, b) => a + b.quantity);
      drink[s] = n;
      drinkLabels[s] = BottleFilter.label('drink', s);
    }
    for (var y = now; y <= now + 15; y++) {
      final n = bottles
          .where((b) => b.drinkableIn(y))
          .fold<int>(0, (a, b) => a + b.quantity);
      if (n > 0) {
        drink['y$y'] = n;
        drinkLabels['y$y'] = '$y';
      }
    }

    final vintages = _options((b) => [b.vintage?.toString() ?? '']);
    final sortedVintages = Map.fromEntries(
        vintages.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));

    final columns = {
      for (final c in rackColumns.keys)
        c: bottles
            .where((b) => columnOf(b.drawer) == c)
            .fold<int>(0, (s, b) => s + b.quantity)
    };
    final drawerCounts = <String, int>{};
    for (final code in allDrawerCodes) {
      final n = bottles
          .where((b) => b.drawer == code)
          .fold<int>(0, (s, b) => s + b.quantity);
      if (n > 0) drawerCounts[code] = n;
    }

    final shown = totalCount(_f.apply(bottles));

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              _section('type', types,
                  avatar: (t) => CircleAvatar(
                      backgroundColor: typeBackground(t),
                      radius: 8)),
              _section('drink', drink, labels: drinkLabels),
              _section('vintage', sortedVintages),
              _section('country', _options((b) => [b.country])),
              _section('grape', _options((b) => b.grapeList)),
              _section('producer', _options((b) => [b.producer])),
              _section('people', _options((b) => b.peopleList)),
              _section(
                  'pairing',
                  _options((b) => splitList(b.pairing).where((x) => pairingOptions
                      .any((o) => o.toLowerCase() == x.toLowerCase())))),
              _section('column', columns),
              _section('drawer', drawerCounts),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _set(_f.cleared()),
                  child: const Text('Clear all'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Show $shown bottles'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
