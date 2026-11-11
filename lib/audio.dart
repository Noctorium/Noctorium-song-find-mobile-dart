/// Listening, which is Android's to do: the microphone, or what the phone itself is playing. Kotlin records
/// (MainActivity.kt, Recorder.kt, CaptureService.kt) and hands back 16 kHz mono samples.
library;

import 'package:flutter/services.dart';

import 'providers.dart';
import 'store.dart';

/// What the app needs from the phone. A fake stands in for it in the tests.
abstract class Phone {
  Future<Clip> record(Source source, int seconds, void Function(double level, double fraction) progress);
  Future<void> stop();
  Future<bool> systemAudioSupported();
  Future<String> updatesFolder();

  /// Null when Android's installer opened; why not, otherwise.
  Future<String?> install(String path);

  /// A notification saying how a search went, which opens Song Find when tapped; [cover] is a picture's
  /// address to show with it.
  Future<void> notify(String title, String body, {String? cover});
}

class AndroidPhone implements Phone {
  AndroidPhone() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final args = call.arguments as Map;
        _progress?.call((args['level'] as num).toDouble(), (args['fraction'] as num).toDouble());
      }
    });
  }

  static const _channel = MethodChannel('noctorium/song-find');
  void Function(double, double)? _progress;

  @override
  Future<Clip> record(Source source, int seconds, void Function(double, double) progress) async {
    _progress = progress;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('record', {
        'source': source == Source.system ? 'system' : 'mic',
        'seconds': seconds,
      });
      return Clip.fromPcm(bytes ?? Uint8List(0));
    } on PlatformException catch (e) {
      throw ListenError(e.message ?? 'Nothing could be recorded.');
    } finally {
      _progress = null;
    }
  }

  @override
  Future<void> stop() => _channel.invokeMethod('stop');

  @override
  Future<bool> systemAudioSupported() async => await _channel.invokeMethod<bool>('systemAudioSupported') ?? false;

  @override
  Future<String> updatesFolder() async => (await _channel.invokeMethod<String>('updatesFolder'))!;

  @override
  Future<String?> install(String path) => _channel.invokeMethod<String>('install', {'path': path});

  @override
  Future<void> notify(String title, String body, {String? cover}) =>
      _channel.invokeMethod('notify', {'title': title, 'body': body, 'cover': cover});
}

class ListenError implements Exception {
  ListenError(this.message);
  final String message;

  @override
  String toString() => message;
}
