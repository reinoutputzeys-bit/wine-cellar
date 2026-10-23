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
  bool _search = false;
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
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
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
