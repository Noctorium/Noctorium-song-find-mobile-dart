/// Run before every test file: gives the tests real type to draw with.
///
/// A widget test draws text in a font of boxes unless it is given another, which is fine for finding a
/// widget and useless for a screenshot anybody has to judge. The Flutter SDK carries Roboto -- what Android
/// itself draws with -- and Material's icon font, so they are loaded from there rather than copied into this
/// repository. Where they cannot be found, the tests still run; only the screenshots would be boxes.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fonts = _materialFonts();
  if (fonts != null) {
    await _load('Roboto', [
      for (final weight in ['light', 'regular', 'medium', 'bold', 'black']) File('${fonts.path}/roboto-$weight.ttf'),
    ]);
    await _load('MaterialIcons', [File('${fonts.path}/materialicons-regular.otf')]);
  }
  await testMain();
}

/// `bin/cache/artifacts/material_fonts` in the Flutter SDK running these tests.
Directory? _materialFonts() {
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?) '$root/bin/cache/artifacts/material_fonts',
    // flutter_tester lives in bin/cache/artifacts/engine/<platform>/, three folders below the fonts' parent.
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
  ];
  for (final path in candidates) {
    final directory = Directory(path);
    if (File('${directory.path}/roboto-regular.ttf').existsSync()) return directory;
  }
  return null;
}

Future<void> _load(String family, List<File> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}
