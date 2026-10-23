import 'package:flutter/material.dart';

import 'data.dart';
import 'edit_page.dart';
import 'filter.dart';
import 'settings_page.dart';
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

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  List<Bottle> _bottles = [];
  bool _loading = true;

  /// One filter shared by the Rack, Bottles and Photo tabs.
  BottleFilter _filter = BottleFilter();

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

  Future<void> _openBottle(Bottle? b) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => BottleEditPage(bottle: b)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_tab == 0) {
      body = RackView(
        bottles: _bottles,
        filter: _filter,
        onFilterChanged: _setFilter,
        onOpenDrawer: _openDrawer,
      );
    } else if (_tab == 1) {
      body = BottleListView(
        bottles: _bottles,
        filter: _filter,
        onFilterChanged: _setFilter,
        onOpen: _openBottle,
        onChanged: _load,
      );
    } else {
      body = RackPhotoView(
        bottles: _bottles,
        filter: _filter,
        onFilterChanged: _setFilter,
        onChanged: _load,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wine Cellar'),
        actions: [
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
