import 'package:flutter/material.dart';

// ============================================================
// RACK LAYOUT
// Columns in physical order, left to right.
// Each number is the max bottles for that drawer, top drawer first.
// ============================================================
const Map<String, List<int>> rackColumns = {
  'A': [6, 6, 6, 6, 6, 6, 6, 6],
  'B': [6, 6, 3, 3, 3, 3, 3],
  'C': [6, 6, 6, 6, 6, 6],
  'D': [6, 6, 6, 6, 6, 12, 12],
  'E': [6, 6, 6, 6, 6],
  'F': [6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
  'G': [6, 6, 6, 6, 6, 6],
};

/// The rack turns the corner of the L after these columns.
const Set<String> cornerAfter = {'B'};

final List<String> allDrawerCodes = [
  for (final e in rackColumns.entries)
    for (var i = 0; i < e.value.length; i++) '${e.key}${i + 1}',
];

String columnOf(String code) => code.isEmpty ? '' : code.substring(0, 1);

int drawerIndex(String code) {
  final i = allDrawerCodes.indexOf(code);
  return i < 0 ? 9999 : i;
}

int capacityOf(String code) {
  if (code.length < 2) return 0;
  final col = rackColumns[columnOf(code)];
  final i = int.tryParse(code.substring(1)) ?? 0;
  if (col == null || i < 1 || i > col.length) return 0;
  return col[i - 1];
}

int get totalCapacity =>
    rackColumns.values.expand((c) => c).fold(0, (a, b) => a + b);

// ============================================================
// RACK PHOTO (assets/cellar/rack.jpg)
// Size of the photo and where each drawer sits on it, in pixels:
// [left, top, width, height]
// ============================================================
const double rackPhotoWidth = 3750;
const double rackPhotoHeight = 1700;

const Map<String, List<double>> drawerPhotoRects = {
  'A1': [98, 344, 537, 102],
  'A2': [98, 458, 537, 104],
  'A3': [98, 574, 537, 104],
  'A4': [98, 696, 537, 104],
  'A5': [98, 816, 537, 100],
  'A6': [98, 938, 537, 106],
  'A7': [98, 1060, 537, 106],
  'A8': [98, 1178, 537, 114],
  'B1': [714, 348, 299, 214],
  'B2': [714, 580, 299, 214],
  'B3': [714, 800, 299, 146],
  'B4': [714, 958, 299, 129],
  'B5': [714, 1099, 299, 134],
  'B6': [714, 1245, 299, 141],
  'B7': [714, 1392, 299, 149],
  'C1': [1074, 324, 308, 183],
  'C2': [1074, 525, 308, 195],
  'C3': [1074, 733, 308, 189],
  'C4': [1074, 940, 308, 189],
  'C5': [1074, 1142, 308, 195],
  'C6': [1074, 1341, 308, 204],
  'D1': [1492, 332, 547, 95],
  'D2': [1492, 440, 547, 103],
  'D3': [1492, 552, 547, 107],
  'D4': [1492, 665, 547, 107],
  'D5': [1492, 781, 547, 104],
  'D6': [1492, 889, 547, 192],
  'D7': [1492, 1096, 547, 196],
  'E1': [2129, 322, 586, 97],
  'E2': [2129, 431, 586, 105],
  'E3': [2129, 552, 586, 115],
  'E4': [2129, 674, 586, 109],
  'E5': [2129, 789, 586, 115],
  'F1': [2793, 331, 515, 100],
  'F2': [2793, 444, 515, 100],
  'F3': [2793, 558, 515, 101],
  'F4': [2793, 672, 515, 100],
  'F5': [2793, 783, 515, 104],
  'F6': [2793, 894, 515, 98],
  'F7': [2793, 1003, 515, 103],
  'F8': [2793, 1117, 515, 108],
  'F9': [2793, 1236, 515, 106],
  'F10': [2793, 1347, 515, 116],
  'G1': [3389, 320, 304, 162],
  'G2': [3389, 496, 304, 185],
  'G3': [3389, 692, 304, 186],
  'G4': [3389, 889, 304, 200],
  'G5': [3389, 1095, 304, 190],
  'G6': [3389, 1292, 304, 199],
};

Rect? drawerPhotoRect(String code) {
  final r = drawerPhotoRects[code];
  if (r == null) return null;
  return Rect.fromLTWH(r[0], r[1], r[2], r[3]);
}

// ============================================================
// WINE TYPES
// ============================================================
const List<String> wineTypes = ['Red', 'White', 'Sparkling', 'Other'];

/// Older entries may use other names (Rosé, Sweet…): those count as Other.
String categoryOf(String type) => wineTypes.contains(type) ? type : 'Other';

Color typeBackground(String type) {
  switch (categoryOf(type)) {
    case 'Red':
      return const Color(0xFF8E1B2C);
    case 'White':
      return const Color(0xFFF3EBC2);
    case 'Sparkling':
      return const Color(0xFFE6D48A);
    default:
      return const Color(0xFF8A7F9E);
  }
}

Color typeForeground(String type) {
  switch (categoryOf(type)) {
    case 'Red':
    case 'Other':
      return Colors.white;
    default:
      return const Color(0xFF3E2F12);
  }
}
