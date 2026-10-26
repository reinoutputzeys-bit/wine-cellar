import 'dart:async';

import 'package:flutter/material.dart';

import 'data.dart';
import 'edit_page.dart';
import 'filter.dart';
import 'settings_page.dart';
import 'sync.dart';
import 'views.dart';

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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _tab = 0;
  List<Bottle> _bottles = [];
  bool _loading = true;

  /// Which list the Bottles tab shows.
  String _listStatus = statusCellar;

  List<Bottle> get _cellar => _bottles.where((b) => b.inCellar).toList();

  /// One filter shared by the Rack, Bottles and Photo tabs.
  BottleFilter _filter = BottleFilter();

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    Sync.instance.onRemoteChange = _load;
    Sync.instance.init().then((_) => Sync.instance.syncNow());
    // While the app is open, look for the other phone's changes now and then.
    _syncTimer = Timer.periodic(
        const Duration(minutes: 2), (_) => Sync.instance.syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Sync.instance.syncNow();
  }

  void _syncTapped() {
    final st = Sync.instance.state.value;
    if (st.phase == SyncPhase.error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(st.message)));
    }
    Sync.instance.syncNow();
  }

  Future<void> _load() async {
    final b = await CellarDb.all();
    if (!mounted) return;
    setState(() {
      _bottles = b;
      _loading = false;
    });
  }

  void _setFilter(BottleFilter f) => setState(() => _filter = f);

  Future<void> _openDrawer(String code) async {
    final f = _filter;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawerPage(
          code: code,
          highlight: f.limitsWines ? f.matches : null,
        ),
      ),
    );
    _load();
  }

  Future<void> _openBottle(Bottle? b, {String status = statusCellar}) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BottleEditPage(bottle: b, status: status)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_tab == 0) {
      body = RackView(
        bottles: _cellar,
        filter: _filter,
        onFilterChanged: _setFilter,
        onOpenDrawer: _openDrawer,
      );
    } else if (_tab == 1) {
      body = BottleListView(
        bottles: _bottles,
        status: _listStatus,
        onStatusChanged: (s) => setState(() => _listStatus = s),
        filter: _filter,
        onFilterChanged: _setFilter,
        onOpen: _openBottle,
        onChanged: _load,
      );
    } else {
      body = RackPhotoView(
        bottles: _cellar,
        filter: _filter,
        onFilterChanged: _setFilter,
        onChanged: _load,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wine Cellar'),
        actions: [
          ValueListenableBuilder<SyncState>(
            valueListenable: Sync.instance.state,
            builder: (context, st, _) {
              if (st.phase == SyncPhase.off) return const SizedBox.shrink();
              final icon = switch (st.phase) {
                SyncPhase.syncing => Icons.cloud_sync_outlined,
                SyncPhase.error => Icons.cloud_off_outlined,
                _ => Icons.cloud_done_outlined,
              };
              return IconButton(
                tooltip: st.phase == SyncPhase.error
                    ? st.message
                    : 'Shared cellar: tap to sync now',
                icon: Icon(icon,
                    color: st.phase == SyncPhase.error ? Colors.orange : null),
                onPressed: _syncTapped,
              );
            },
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()));
              _load(); // a restored backup changes the bottles
            },
          ),
        ],
      ),
      body: body,
      floatingActionButton: _tab == 2 ||
              (_tab == 1 && _listStatus == statusArchive)
          ? null
          : (_tab == 1 && _listStatus == statusWish)
              ? FloatingActionButton.extended(
                  onPressed: () => _openBottle(null, status: statusWish),
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('Add to wishlist'),
                )
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
