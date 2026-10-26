import 'package:flutter/material.dart';

import 'backup.dart';
import 'data.dart';
import 'lookup.dart';
import 'sync.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _search = false;
  String? _lastBackup;
  bool _show = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _key.text = await CellarDb.getSetting('gemini_key') ?? '';
    _model.text = await CellarDb.getSetting('gemini_model') ?? defaultModel;
    _search = (await CellarDb.getSetting('gemini_search')) == '1';
    _lastBackup = await CellarDb.getSetting('last_backup');
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  String _lastBackupText() {
    final d = DateTime.tryParse(_lastBackup ?? '');
    if (d == null) return 'No backup made yet.';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Last backup: ${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Future<void> _export() async {
    await Backup.export(context);
    final v = await CellarDb.getSetting('last_backup');
    if (mounted) setState(() => _lastBackup = v);
  }

  bool _testing = false;

  Future<void> _testKey() async {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    setState(() => _testing = true);
    String result;
    try {
      final model = _model.text.trim().isEmpty ? defaultModel : _model.text.trim();
      final found = await WineLookup.testKey(key, model);
      result = '✅ The key works. Test answer: $found';
    } catch (e) {
      result = '⚠️ $e';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Key test'),
        content: SelectableText(result),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    await Backup.restore(context);
  }

  Future<void> _save() async {
    await CellarDb.setSetting('gemini_key', _key.text.trim());
    await CellarDb.setSetting('gemini_model',
        _model.text.trim().isEmpty ? defaultModel : _model.text.trim());
    await CellarDb.setSetting('gemini_search', _search ? '1' : '0');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Online wine lookup (Google Gemini)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'When you add a bottle, Gemini reads the label photo and fills in the details. '
                  'Get a free API key at aistudio.google.com (no credit card needed).',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _key,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Gemini API key',
                    hintText: 'AIza…',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Also search Google'),
                  subtitle: const Text(
                      'More up-to-date prices and details, but only works when billing is '
                      'turned on for your key. Leave off to stay completely free.'),
                  value: _search,
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _testKey,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: Text(_testing ? 'Testing…' : 'Test key'),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                ),
                const Divider(height: 40),
                const SharedCellarSection(),
                const Divider(height: 40),
                Text('Backup',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'Saves all bottles and their photos in one file. Choose "Drive" in the '
                  'share menu to keep it safe in Google Drive. Your Gemini key is not included.',
                ),
                const SizedBox(height: 8),
                Text(_lastBackupText(),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _export,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Make backup'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore from backup'),
                ),
              ],
            ),
    );
  }
}


// ============================================================
// SHARED CELLAR (both phones see and manage the same cellar)
// ============================================================
class SharedCellarSection extends StatefulWidget {
  const SharedCellarSection({super.key});

  @override
  State<SharedCellarSection> createState() => _SharedCellarSectionState();
}

class _SharedCellarSectionState extends State<SharedCellarSection> {
  final _project = TextEditingController();
  final _apiKey = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _connected = false;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _project.text = await CellarDb.getSetting('sync_project') ?? '';
    _apiKey.text = await CellarDb.getSetting('sync_api_key') ?? '';
    _email.text = await CellarDb.getSetting('sync_email') ?? '';
    _connected = await Sync.instance.isConnected;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _project.dispose();
    _apiKey.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _show(String title, String text) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    if ([_project, _apiKey, _email, _password].any((c) => c.text.trim().isEmpty)) {
      _show('Shared cellar', 'Please fill in all four fields.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Sync.instance.connect(
        projectId: _project.text.trim(),
        apiKey: _apiKey.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      _password.clear();
      if (!mounted) return;
      setState(() => _connected = true);
      _show('Shared cellar',
          '✅ Connected. Your bottles are now shared, and changes from the other phone will appear here.');
    } catch (e) {
      if (mounted) _show('Could not connect', '⚠️ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop sharing on this phone?'),
        content: const Text(
            'Your bottles stay on this phone, but changes are no longer shared. '
            'You can connect again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop sharing')),
        ],
      ),
    );
    if (ok != true) return;
    await Sync.instance.disconnect();
    if (mounted) setState(() => _connected = false);
  }

  String _time(DateTime? d) {
    if (d == null) return 'not yet';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final title = Text('Shared cellar',
        style: Theme.of(context).textTheme.titleMedium);

    if (_connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 8),
          Text('Connected as ${_email.text} (project ${_project.text}). '
              'Both phones see and manage the same bottles.'),
          const SizedBox(height: 8),
          ValueListenableBuilder<SyncState>(
            valueListenable: Sync.instance.state,
            builder: (context, st, _) => Text(
              switch (st.phase) {
                SyncPhase.syncing => 'Syncing…',
                SyncPhase.error => '⚠️ ${st.message}',
                _ => 'Last sync: ${_time(st.lastSync)}',
              },
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => Sync.instance.syncNow(),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Stop sharing on this phone'),
          ),
        ],
      );
    }

    InputDecoration deco(String label, [String? hint]) => InputDecoration(
        labelText: label, hintText: hint, border: const OutlineInputBorder());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 8),
        const Text(
            'Share the cellar with someone else, so you both see and manage the same bottles. '
            'Uses a free Google Firebase project. Each person signs in with their own email.'),
        const SizedBox(height: 12),
        TextField(
            controller: _project,
            autocorrect: false,
            decoration: deco('Firebase Project ID', 'wine-cellar-12345')),
        const SizedBox(height: 8),
        TextField(
            controller: _apiKey,
            autocorrect: false,
            decoration: deco('Web API key', 'AIza…')),
        const SizedBox(height: 8),
        TextField(
            controller: _email,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: deco('Your email')),
        const SizedBox(height: 8),
        TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: deco('Your password')),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_outlined),
          label: Text(_busy ? 'Connecting…' : 'Connect'),
        ),
      ],
    );
  }
}
