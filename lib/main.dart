e now create the main starting file of the app.

Click Add file → Create new file.
In the “Name your file…” box, type exactly this (including the folder):

lib/main.dart

In the big text area, paste this code:
dart
import 'package:flutter/material.dart';

void main() {
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D4037), // warm wood brown
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'Wine Cellar App\nComing soon...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}
