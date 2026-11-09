/// Asks the real providers about a recording: `dart run tool/identify.dart <16 kHz mono s16le file>`.
/// The phone's own code, run on a computer, to check it against the real services.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:noctorium_song_find/providers.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('usage: dart run tool/identify.dart <16 kHz mono s16le file>');
    exit(2);
  }
  final clip = Clip.fromPcm(Uint8List.fromList(File(arguments.first).readAsBytesSync()));
  final providers = Providers(http.Client());
  var found = false;
  for (final provider in Provider.values) {
    final answer = await providers.ask(provider, clip, const Keys());
    switch (answer) {
      case Found(:final song):
        found = true;
        stdout.writeln('${provider.label}: ${song.artist} -- ${song.title} (${song.album ?? 'no album'})');
      case Unknown():
        stdout.writeln('${provider.label}: did not know it');
      case Failed(:final why):
        stdout.writeln(why);
    }
  }
  exit(found ? 0 : 1);
}
