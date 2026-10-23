import 'package:flutter/material.dart';

import 'data.dart';
import 'lookup.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _show = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _key.text = await CellarDb.getSetting('api_key') ?? '';
    _model.text = await CellarDb.getSetting('model') ?? defaultModel;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await CellarDb.setSetting('api_key', _key.text.trim());
    await CellarDb.setSetting(
        'model', _model.text.trim().isEmpty ? defaultModel : _model.text.trim());
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
                Text('Online wine lookup',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'When you add a bottle, the app can read the label photo and search the web '
                  '(Vivino, Wine-Searcher, producer sites…) to fill in the details. '
                  'This uses the Claude API with your own key. Each lookup costs a few cents.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _key,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Claude API key',
                    hintText: 'sk-ant-…',
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
                const SizedBox(height: 20),
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
