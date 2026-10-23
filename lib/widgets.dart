import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data.dart';
import 'edit_page.dart';
import 'rack.dart';

// ============================================================
// CATEGORY BADGES (red / white / sparkling / other)
// ============================================================
class BubblesPainter extends CustomPainter {
  const BubblesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x99FFFFFF);
    final ring = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, size.shortestSide * 0.04);
    // Fixed bubble positions (fractions of the badge) so it looks the same everywhere.
    const bubbles = [
      [0.15, 0.78, 0.07],
      [0.30, 0.45, 0.05],
      [0.80, 0.70, 0.08],
      [0.70, 0.25, 0.05],
      [0.12, 0.25, 0.04],
      [0.55, 0.88, 0.05],
      [0.90, 0.40, 0.04],
    ];
    for (final b in bubbles) {
      final c = Offset(b[0] * size.width, b[1] * size.height);
      final r = b[2] * size.shortestSide * 1.6;
      canvas.drawCircle(c, r, b[2] > 0.06 ? ring : paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(
      {super.key, required this.type, required this.count, this.size = 20});

  final String type;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = typeBackground(type);
    final fg = typeForeground(type);
    Widget box = Container(
      width: size * 1.15,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: type == 'White'
            ? Border.all(color: const Color(0xFFCDBF7A), width: 0.8)
            : null,
      ),
      child: CustomPaint(
        painter: type == 'Sparkling' ? const BubblesPainter() : null,
        child: Center(
          child: Text(
            '$count',
            style: TextStyle(
              color: fg,
              fontSize: size * 0.6,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ),
    );
    if (count == 0) box = Opacity(opacity: 0.3, child: box);
    return box;
  }
}

class CategoryCounts extends StatelessWidget {
  const CategoryCounts({super.key, required this.counts, this.size = 20});

  final Map<String, int> counts;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < wineTypes.length; i++) ...[
          if (i > 0) SizedBox(width: size * 0.15),
          CategoryBadge(
              type: wineTypes[i],
              count: counts[wineTypes[i]] ?? 0,
              size: size),
        ],
      ],
    );
  }
}

// ============================================================
// SUMMARY (totals at the top of a tab)
// ============================================================
class SummaryBar extends StatelessWidget {
  const SummaryBar({super.key, required this.bottles, required this.filtered});

  final List<Bottle> bottles;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final n = totalCount(bottles);
    final value = totalValue(bottles);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Text(filtered ? '$n matching' : '$n bottles',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 10),
          CategoryCounts(counts: countByCategory(bottles), size: 20),
          const Spacer(),
          if (value > 0)
            Text(formatMoney(value),
                style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

// ============================================================
// DRAWER TILE (rack map and photo overlay)
// ============================================================
class DrawerTile extends StatelessWidget {
  const DrawerTile({
    super.key,
    required this.code,
    required this.used,
    required this.capacity,
    required this.counts,
    this.dimmed = false,
    this.highlighted = false,
    this.onTap,
    this.width = 96,
    this.height = 56,
  });

  final String code;
  final int used;
  final int capacity;

  /// Bottles per category shown in the 4 badges (already filtered).
  final Map<String, int> counts;
  final bool dimmed;
  final bool highlighted;
  final VoidCallback? onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final over = used > capacity;
    final fill = capacity == 0 ? 0.0 : (used / capacity).clamp(0.0, 1.0);
    final Color bg = over
        ? Colors.red.shade100
        : Color.lerp(const Color(0xFFFBF5EE), const Color(0xFFE2C9AE), fill)!;
    final tile = Material(
      color: bg,
      elevation: highlighted ? 4 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: highlighted
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFFD7C2AA),
          width: highlighted ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(code,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      Text('$used/$capacity',
                          style: TextStyle(
                              fontSize: 12,
                              color: over
                                  ? Colors.red.shade800
                                  : Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  CategoryCounts(counts: counts, size: 17),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: dimmed ? 0.3 : 1,
      child: tile,
    );
  }
}

// ============================================================
// BOTTLE PHOTO
// ============================================================
class BottleThumb extends StatelessWidget {
  const BottleThumb(
      {super.key,
      this.photoPath,
      required this.type,
      this.width = 48,
      this.height = 48});

  final String? photoPath;
  final String type;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path),
          width: width,
          height: height,
          fit: BoxFit.cover,
          cacheWidth: (width * 3).round(),
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: typeBackground(type),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(
        painter: categoryOf(type) == 'Sparkling' ? const BubblesPainter() : null,
        child: Icon(Icons.wine_bar, color: typeForeground(type)),
      ),
    );
  }
}

// ============================================================
// BOTTLE CARD (photo + data + -1/+1)
// ============================================================
class BottleCard extends StatelessWidget {
  const BottleCard({
    super.key,
    required this.bottle,
    required this.onTap,
    required this.onChanged,
    this.showDrawer = true,
  });

  final Bottle bottle;
  final VoidCallback onTap;
  final VoidCallback onChanged;
  final bool showDrawer;

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: Colors.black54),
            const SizedBox(width: 4),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final b = bottle;
    final place = [b.country, b.region].where((s) => s.isNotEmpty).join(', ');
    final status = b.drinkStatus;
    final statusText = status == 'now'
        ? 'ready'
        : status == 'wait'
            ? 'not ready yet'
            : status == 'past'
                ? 'past its best'
                : '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () async {
          if (await copyBottleToDrawer(context, b)) onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BottleThumb(
                  photoPath: b.photoPath, type: b.type, width: 64, height: 92),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CategoryBadge(type: b.category, count: b.quantity, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(b.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: 'Search on Google',
                          icon: const Icon(Icons.travel_explore,
                              size: 20, color: Color(0xFF1A73E8)),
                          onPressed: () => searchOnGoogle(context, b),
                        ),
                      ],
                    ),
                    if (b.producer.isNotEmpty)
                      Text(b.producer,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    if (place.isNotEmpty) _line(Icons.place_outlined, place),
                    if (b.grapes.isNotEmpty) _line(Icons.eco_outlined, b.grapes),
                    if (b.drinkWindow.isNotEmpty)
                      _line(Icons.schedule,
                          'Drink ${b.drinkWindow}${statusText.isEmpty ? '' : ' · $statusText'}'),
                    if (b.pairing.isNotEmpty)
                      _line(Icons.restaurant_outlined, b.pairing),
                    if (b.drinkWith.isNotEmpty)
                      _line(Icons.people_outline, b.drinkWith),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (b.price != null)
                          Text(formatMoney(b.price!),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                        if (b.price != null && showDrawer)
                          const Text('  ·  ', style: TextStyle(fontSize: 13)),
                        if (showDrawer)
                          Text('Drawer ${b.drawer}',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black54)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'One more',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () async {
                      if (await changeQuantity(context, b, 1)) onChanged();
                    },
                  ),
                  Text('${b.quantity}',
                      style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'One less',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      if (await changeQuantity(context, b, -1)) onChanged();
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy to another drawer',
                    icon: const Icon(Icons.copy_all_outlined, size: 20),
                    onPressed: () async {
                      if (await copyBottleToDrawer(context, b)) onChanged();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CONTENTS OF ONE DRAWER (used by the drawer page and the photo tab)
// ============================================================
class DrawerContents extends StatefulWidget {
  const DrawerContents({
    super.key,
    required this.code,
    required this.onChanged,
    this.scrollController,
    this.highlight,
  });

  final String code;
  final VoidCallback onChanged;
  final ScrollController? scrollController;

  /// Bottles matching the active filter are shown first and marked.
  final bool Function(Bottle)? highlight;

  @override
  State<DrawerContents> createState() => _DrawerContentsState();
}

class _DrawerContentsState extends State<DrawerContents> {
  List<Bottle> _bottles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await CellarDb.all();
    if (!mounted) return;
    setState(() {
      _bottles = all.where((b) => b.drawer == widget.code).toList();
      _loading = false;
    });
  }

  Future<void> _changed() async {
    await _load();
    widget.onChanged();
  }

  Future<void> _edit(Bottle? b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => BottleEditPage(bottle: b, initialDrawer: widget.code)),
    );
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final cap = capacityOf(widget.code);
    final used = totalCount(_bottles);
    final value = totalValue(_bottles);
    final hl = widget.highlight;
    final list = [..._bottles];
    if (hl != null) {
      list.sort((a, b) => (hl(b) ? 1 : 0).compareTo(hl(a) ? 1 : 0));
    }
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Text('Drawer ${widget.code}',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              CategoryCounts(counts: countByCategory(_bottles), size: 22),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$used of $cap spots used${value > 0 ? ' · ${formatMoney(value)}' : ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: LinearProgressIndicator(
            value: cap == 0 ? 0 : (used / cap).clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('This drawer is empty')),
          )
        else
          for (final b in list)
            Opacity(
              opacity: hl == null || hl(b) ? 1 : 0.45,
              child: BottleCard(
                bottle: b,
                showDrawer: false,
                onTap: () => _edit(b),
                onChanged: _changed,
              ),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: OutlinedButton.icon(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('Add a bottle to this drawer'),
          ),
        ),
      ],
    );
  }
}
