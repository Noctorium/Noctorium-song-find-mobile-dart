/// Noctorium Song Find: which song is playing, heard through the microphone or taken from what the phone
/// itself is playing, asked of Shazam, AudD and ACRCloud. The phone's half of a pair with the desktop's.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'audio.dart';
import 'finder.dart';
import 'store.dart';

/// This build's version: `--build-name` when the release passed one, pubspec.yaml's otherwise.
const String version = appBuildName ?? '0.0.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final finder = SongFinder(store: await Store.open(), phone: AndroidPhone(), client: http.Client(), version: version);
  runApp(SongFindApp(finder: finder));
  finder.start();
}
