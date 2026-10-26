import 'package:flutter/material.dart';

import 'data.dart';
import 'filter.dart';
import 'rack.dart';
import 'widgets.dart';

// ============================================================
// RACK TAB
// ============================================================
class RackView extends StatelessWidget {
  const RackView({
    super.key,
    required this.bottles,
    required this.filter,
    required this.onFilterChanged,
    required this.onOpenDrawer,
  });

  final List<Bottle> bottles;
  final BottleFilter filter;
  final ValueChanged<BottleFilter> onFilterChanged;
  final void Function(String code) onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final matching = filter.apply(bottles);
    final children = <Widget>[];
    for (final e in rackColumns.entries) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            Text(e.key, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            for (var i = 0; i < e.value.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _tile('${e.key}${i + 1}', e.value[i], matching),
              ),
          ],
        ),
      ));
      if (cornerAfter.contains(e.key)) {
        children.add(Container(
          width: 4,
          height: 480,
          margin: const EdgeInsets.only(left: 6, right: 6, top: 34),
          decoration: BoxDecoration(
            color: Colors.brown.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ));
      }
    }
    return Column(
      children: [
        FilterBar(filter: filter, bottles: bottles, onChanged: onFilterChanged),
        SummaryBar(bottles: matching, filtered: filter.isActive),
        const Divider(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(String code, int capacity, List<Bottle> matching) {
    final inDrawer = bottles.where((b) => b.drawer == code);
    final matchInDrawer = matching.where((b) => b.drawer == code).toList();
    final dimmed = !filter.drawerAllowed(code) ||
        (filter.limitsWines && matchInDrawer.isEmpty);
    return DrawerTile(
      code: code,
      used: totalCount(inDrawer),
      capacity: capacity,
      counts: countByCategory(matchInDrawer),
      dimmed: dimmed,
      highlighted: filter.limitsWines && matchInDrawer.isNotEmpty,
      height: capacity >= 12 ? 70 : 54,
      onTap: () => onOpenDrawer(code),
    );
  }
}

// ============================================================
// BOTTLES TAB
// ============================================================
class BottleListView extends StatelessWidget {
  const BottleListView({
    super.key,
    required this.bottles,
    required this.status,
    required this.onStatusChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.onOpen,
    required this.onChanged,
  });

  /// All entries (cellar, wishlist and archive).
  final List<Bottle> bottles;

  /// Which list is shown: statusCellar, statusWish or statusArchive.
  final String status;
  final ValueChanged<String> onStatusChanged;
  final BottleFilter filter;
  final ValueChanged<BottleFilter> onFilterChanged;
  final void Function(Bottle) onOpen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final inList = bottles.where((b) => b.status == status).toList();
    final list = filter.apply(inList)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    int n(String s) => bottles.where((b) => b.status == s).length;
    final empty = switch (status) {
      statusWish => 'Your wishlist is empty. Tap “Add to wishlist”.',
      statusArchive =>
        'Nothing archived yet. When you finish a wine, its details are kept here.',
      _ => 'No bottles yet. Tap “Add bottle” to start.',
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: statusCellar,
                  icon: const Icon(Icons.wine_bar, size: 18),
                  label: Text('Cellar ${totalCount(bottles.where((b) => b.inCellar))}')),
              ButtonSegment(
                  value: statusWish,
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: Text('Wishlist ${n(statusWish)}')),
              ButtonSegment(
                  value: statusArchive,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text('Archive ${n(statusArchive)}')),
            ],
            selected: {status},
            onSelectionChanged: (s) => onStatusChanged(s.first),
          ),
        ),
        FilterBar(
          filter: filter,
          bottles: inList,
          onChanged: onFilterChanged,
          showSearch: true,
        ),
        SummaryBar(bottles: list, filtered: filter.isActive, status: status),
        const Divider(height: 8),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      inList.isEmpty ? empty : 'Nothing matches your filter',
                      textAlign: TextAlign.center),
                ))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  itemBuilder: (_, i) => BottleCard(
                    bottle: list[i],
                    onTap: () => onOpen(list[i]),
                    onChanged: onChanged,
                  ),
                ),
        ),
      ],
    );
  }
}

// ============================================================
// PHOTO TAB
// ============================================================
class RackPhotoView extends StatefulWidget {
  const RackPhotoView({
    super.key,
    required this.bottles,
    required this.filter,
    required this.onFilterChanged,
    required this.onChanged,
  });

  final List<Bottle> bottles;
  final BottleFilter filter;
  final ValueChanged<BottleFilter> onFilterChanged;
  final VoidCallback onChanged;

  @override
  State<RackPhotoView> createState() => _RackPhotoViewState();
}

class _RackPhotoViewState extends State<RackPhotoView>
    with TickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _zoom = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  late final AnimationController _pull = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));
  Animation<Matrix4>? _zoomAnim;
  String? _open;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final a = _zoomAnim;
      if (a != null) _tc.value = a.value;
    });
  }

  @override
  void dispose() {
    _zoom.dispose();
    _pull.dispose();
    _tc.dispose();
    super.dispose();
  }

  Future<void> _animateTo(Matrix4 target) async {
    _zoomAnim = Matrix4Tween(begin: _tc.value.clone(), end: target)
        .animate(CurvedAnimation(parent: _zoom, curve: Curves.easeInOutCubic));
    await _zoom.forward(from: 0);
  }

  Future<void> _openDrawer(String code, Size viewport, double k) async {
    final r = drawerPhotoRect(code);
    if (r == null || _open != null) return;
    final rd = Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k);
    final saved = _tc.value.clone();
    final s = [
      viewport.width * 0.8 / rd.width,
      viewport.height * 0.2 / rd.height,
      4.0,
    ].reduce((a, b) => a < b ? a : b).clamp(1.0, 4.0);
    final tx = viewport.width / 2 - rd.center.dx * s;
    final ty = viewport.height * 0.2 - rd.center.dy * s;
    final target = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(tx, ty, 0);

    setState(() => _open = code);
    _animateTo(target);
    _pull.forward(from: 0);

    final f = widget.filter;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      barrierColor: Colors.black12,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.58,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (ctx, sc) => DrawerContents(
          code: code,
          onChanged: widget.onChanged,
          scrollController: sc,
          highlight: f.limitsWines ? f.matches : null,
        ),
      ),
    );

    if (!mounted) return;
    await _pull.reverse();
    if (!mounted) return;
    await _animateTo(saved);
    if (mounted) setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final matching = filter.apply(widget.bottles);
    return LayoutBuilder(builder: (context, c) {
      final viewport = Size(c.maxWidth, c.maxHeight);
      final k = c.maxHeight / rackPhotoHeight;
      final layers = <Widget>[
        Positioned.fill(
          child: Image.asset(
            'assets/cellar/rack.jpg',
            fit: BoxFit.fill,
            errorBuilder: (context, error, stack) => const ColoredBox(
              color: Color(0xFFEFE6DC),
              child: Center(
                child: Text('Upload rack.jpg to assets/cellar/',
                    style: TextStyle(fontSize: 60)),
              ),
            ),
          ),
        ),
      ];

      for (final code in allDrawerCodes) {
        final r = drawerPhotoRect(code);
        if (r == null) continue;
        final inDrawer = widget.bottles.where((b) => b.drawer == code);
        final match = matching.where((b) => b.drawer == code).toList();
        final dimmed = !filter.drawerAllowed(code) ||
            (filter.limitsWines && match.isEmpty);
        final hit = filter.limitsWines && match.isNotEmpty;

        // Tap anywhere on the drawer front.
        layers.add(Positioned.fromRect(
          rect: r,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openDrawer(code, viewport, k),
            child: hit
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.amberAccent, width: 7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                : null,
          ),
        ));

        // Small tile on the drawer front.
        final h = (r.height * 0.72).clamp(40.0, 92.0);
        final w = (h * 1.9).clamp(0.0, r.width * 0.62);
        layers.add(Positioned(
          left: r.right - w - 10,
          top: r.center.dy - h / 2,
          width: w,
          height: h,
          child: DrawerTile(
            code: code,
            used: totalCount(inDrawer),
            capacity: capacityOf(code),
            counts: countByCategory(match),
            dimmed: dimmed,
            width: w,
            height: h,
            onTap: () => _openDrawer(code, viewport, k),
          ),
        ));
      }

      // Opened drawer: darken the rest and pull the drawer towards you.
      final open = _open;
      final openRect = open == null ? null : drawerPhotoRect(open);
      if (openRect != null) {
        layers.add(Positioned.fill(
          child: AnimatedBuilder(
            animation: _pull,
            builder: (context, _) => IgnorePointer(
              child: ColoredBox(
                  color: Color.fromRGBO(0, 0, 0, 0.55 * _pull.value)),
            ),
          ),
        ));
        layers.add(Positioned.fromRect(
          rect: openRect,
          child: AnimatedBuilder(
            animation: _pull,
            builder: (context, _) =>
                ColoredBox(color: Color.fromRGBO(20, 12, 6, _pull.value)),
          ),
        ));
        layers.add(Positioned.fromRect(
          rect: openRect,
          child: AnimatedBuilder(
            animation: _pull,
            builder: (context, child) {
              final t = Curves.easeOutBack.transform(_pull.value);
              return Transform.translate(
                offset: Offset(0, openRect.height * 0.35 * t),
                child: Transform.scale(scale: 1 + 0.12 * t, child: child),
              );
            },
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 30,
                      offset: Offset(0, 18)),
                ],
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: rackPhotoWidth,
                  maxWidth: rackPhotoWidth,
                  minHeight: rackPhotoHeight,
                  maxHeight: rackPhotoHeight,
                  child: Transform.translate(
                    offset: Offset(-openRect.left, -openRect.top),
                    child: Image.asset('assets/cellar/rack.jpg',
                        width: rackPhotoWidth,
                        height: rackPhotoHeight,
                        fit: BoxFit.fill),
                  ),
                ),
              ),
            ),
          ),
        ));
      }

      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              minScale: 0.5,
              maxScale: 6,
              boundaryMargin: EdgeInsets.symmetric(
                  horizontal: c.maxWidth * 0.3, vertical: c.maxHeight * 0.6),
              child: SizedBox(
                width: rackPhotoWidth * k,
                height: c.maxHeight,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: rackPhotoWidth,
                    height: rackPhotoHeight,
                    child: Stack(children: layers),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Theme.of(context)
                  .colorScheme
                  .surface
                  .withAlpha(220),
              child: FilterBar(
                filter: filter,
                bottles: widget.bottles,
                onChanged: widget.onFilterChanged,
              ),
            ),
          ),
        ],
      );
    });
  }
}
