import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart' show FilePicker, PlatformFile;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams, XFile;

import 'data.dart';
import 'sync.dart';

// ============================================================
// BACKUP FILE FORMAT
// Line 1: {"format": "wine-cellar-backup", "version": 1, ...}
// Every next line: {"bottle": {...}, "photo": "<base64 jpg>" or null}
// One bottle per line keeps memory use low, even with hundreds of photos.
// Your Gemini key is NOT included.
// ============================================================
const String _format = 'wine-cellar-backup';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Backup {
  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Writes all bottles and photos to one file and returns it.
  static Future<File> create() async {
    final bottles = await CellarDb.all();
    final now = DateTime.now();
    final dir = await getTemporaryDirectory();
    final name =
        'wine-cellar-backup-${now.year}-${_two(now.month)}-${_two(now.day)}.winecellar';
    final file = File(p.join(dir.path, name));
    final sink = file.openWrite();
    sink.writeln(jsonEncode({
      'format': _format,
      'version': 1,
      'created': now.toIso8601String(),
      'entries': bottles.length,
      'bottles': totalCount(bottles),
    }));
    for (final b in bottles) {
      final map = b.toMap()
        ..remove('id')
        ..remove('photo_path');
      String? photo;
      final path = b.photoPath;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) photo = base64Encode(await f.readAsBytes());
      }
      sink.writeln(jsonEncode({'bottle': map, 'photo': photo}));
    }
    await sink.flush();
    await sink.close();
    return file;
  }

  /// Opens the share sheet so the backup can be saved to Google Drive etc.
  static Future<void> export(BuildContext context) async {
    final file = await _withProgress(context, 'Making backup…', create);
    if (file == null || !context.mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: 'Wine cellar backup',
    ));
    await CellarDb.setSetting('last_backup', DateTime.now().toIso8601String());
  }

  /// Lets the user pick a backup file and replaces the cellar with it.
  /// Returns true if the cellar was restored.
  static Future<bool> restore(BuildContext context) async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(dialogTitle: 'Choose a wine cellar backup');
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not open the file: $e');
      return false;
    }
    if (picked == null || !context.mounted) return false;

    final lines = StreamIterator(picked
        .readAsByteStream()
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()));

    // Check the first line before asking anything.
    Map<String, dynamic> header;
    try {
      if (!await lines.moveNext()) throw BackupException('This file is empty.');
      final h = jsonDecode(lines.current);
      if (h is! Map<String, dynamic> || h['format'] != _format) {
        throw BackupException('This is not a wine cellar backup.');
      }
      header = h;
    } catch (e) {
      await lines.cancel();
      if (context.mounted) {
        _snack(context, e is BackupException ? e.message : 'This is not a wine cellar backup.');
      }
      return false;
    }
    if (!context.mounted) {
      await lines.cancel();
      return false;
    }

    final created = DateTime.tryParse('${header['created']}');
    final when = created == null
        ? 'unknown date'
        : '${_two(created.day)}/${_two(created.month)}/${created.year}';
    final shared = await Sync.instance.isConnected;
    if (!context.mounted) {
      await lines.cancel();
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
            'Backup from $when with ${header['bottles'] ?? '?'} bottles.\n\n'
            'This replaces everything that is in the app now.'
            '${shared ? '\n\nThe cellar is shared: this also replaces it on the other phone.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      await lines.cancel();
      return false;
    }

    final count = await _withProgress(context, 'Restoring…', () async {
      final docs = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final restored = <Bottle>[];
      final newPhotos = <String>{};
      var i = 0;
      try {
        while (await lines.moveNext()) {
          final line = lines.current.trim();
          if (line.isEmpty) continue;
          final row = jsonDecode(line) as Map<String, dynamic>;
          final map = Map<String, Object?>.from(row['bottle'] as Map);
          final b = Bottle.fromMap(map)..id = null;
          final photo = row['photo'];
          if (photo is String && photo.isNotEmpty) {
            final path = p.join(docs.path, 'bottle_r${stamp}_$i.jpg');
            await File(path).writeAsBytes(base64Decode(photo));
            b.photoPath = path;
            newPhotos.add(path);
          } else {
            b.photoPath = null;
          }
          restored.add(b);
          i++;
        }
      } catch (e) {
        // Clean up half-restored photos; the old cellar stays untouched.
        for (final path in newPhotos) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
        throw BackupException('The backup file is damaged: $e');
      }

      final oldPhotos = (await CellarDb.all())
          .map((b) => b.photoPath)
          .whereType<String>()
          .toSet();
      await CellarDb.replaceAll(restored);
      // Remove photos that belonged to the replaced cellar.
      for (final path in oldPhotos.difference(newPhotos)) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      return totalCount(restored);
    });

    if (count == null) return false;
    if (context.mounted) _snack(context, 'Restored $count bottles');
    return true;
  }

  static void _snack(BuildContext context, String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Runs [work] while showing a small progress dialog.
  /// Returns null (and shows the error) if it fails.
  static Future<T?> _withProgress<T>(
      BuildContext context, String text, Future<T> Function() work) async {
    final nav = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
    try {
      final r = await work();
      nav.pop();
      return r;
    } catch (e) {
      nav.pop();
      if (context.mounted) {
        _snack(context, e is BackupException ? e.message : 'Something went wrong: $e');
      }
      return null;
    }
  }
}
