/// Everything the screens show, and everything they can ask for: listening, asking the providers, the
/// history, the settings, and updating. The screens only draw this and call it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'audio.dart';
import 'providers.dart';
import 'song.dart';
import 'store.dart';
import 'update.dart';

enum Activity { idle, listening, asking }

enum Updating { nothing, downloading, handed, failed }

class SongFinder extends ChangeNotifier {
  SongFinder({required this.store, required this.phone, required this.client, required this.version})
    : providers = Providers(client, version: version),
      settings = store.settings,
      history = store.history;

  final Store store;
  final Phone phone;
  final http.Client client;
  final Providers providers;
  final String version;

  Settings settings;
  List<Entry> history;

  Activity activity = Activity.idle;
  double level = 0;
  double fraction = 0;
  Provider? asking;
  List<(Provider, Answer)> answers = [];
  Song? shown;
  String? problem;
  bool systemAudioSupported = true;

  Release? newer;
  Updating updating = Updating.nothing;
  double downloaded = 0;
  String? updateProblem;

  Future<void> start() async {
    try {
      systemAudioSupported = await phone.systemAudioSupported();
    } catch (_) {}
    notifyListeners();
    if (settings.checkForUpdates) await checkForUpdate();
  }

  Future<bool> checkForUpdate() async {
    newer = await UpdateChecker(client).newerThan(version);
    notifyListeners();
    return newer != null;
  }

  void change(Settings next) {
    settings = next;
    store.saveSettings(next);
    notifyListeners();
  }

  bool get busy => activity != Activity.idle;

  Future<void> listen() async {
    if (busy) {
      await phone.stop();
      return;
    }
    activity = Activity.listening;
    level = 0;
    fraction = 0;
    answers = [];
    problem = null;
    notifyListeners();
    final source = settings.source;
    try {
      final clip = await phone.record(source, settings.seconds, (l, f) {
        level = l;
        fraction = f;
        notifyListeners();
      });
      if (clip.samples.isEmpty || clip.level < .002) {
        problem = source == Source.system
            ? 'Nothing was playing. Play the song on this phone, then listen again.'
            : 'Nothing was heard. Move closer to the sound and try again.';
        return;
      }
      await identify(clip, source == Source.system ? 'Phone audio' : 'Microphone');
    } on ListenError catch (e) {
      problem = e.message;
    } catch (e) {
      problem = 'Something went wrong: $e';
    } finally {
      activity = Activity.idle;
      asking = null;
      notifyListeners();
    }
  }

  Future<void> identify(Clip clip, String source) async {
    activity = Activity.asking;
    for (final provider in settings.inOrder) {
      if (settings.keys.missing(provider) != null) continue;
      asking = provider;
      notifyListeners();
      final answer = await providers.ask(provider, clip, settings.keys);
      answers = [...answers, (provider, answer)];
      notifyListeners();
      if (answer is Found && !settings.askEveryone) break;
    }
    final found = [
      for (final (_, a) in answers)
        if (a is Found) a.song,
    ];
    shown = found.firstOrNull;
    if (found.isEmpty) {
      final failures = [
        for (final (_, a) in answers)
          if (a is Failed) a.why,
      ];
      problem = answers.isEmpty
          ? 'No provider is switched on, or none has what it needs. See Settings.'
          : failures.length == answers.length
          ? failures.join('\n')
          : 'No song was found. Try again closer to the sound, or for longer.';
      return;
    }
    if (settings.keepHistory) {
      final seen = <String>{};
      final now = DateTime.now();
      final added = [
        for (final song in found)
          if (seen.add('${song.title.toLowerCase()}\u0000${song.artist.toLowerCase()}')) Entry(song, now, source),
      ];
      history = [...added, ...history].take(historyMost).toList();
      await store.saveHistory(history);
    }
  }

  void show(Song song) {
    shown = song;
    notifyListeners();
  }

  Future<void> remove(Entry entry) async {
    history = [...history]..remove(entry);
    await store.saveHistory(history);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history = [];
    await store.saveHistory(history);
    notifyListeners();
  }

  Future<void> installUpdate() async {
    final release = newer;
    if (release == null || updating == Updating.downloading) return;
    updating = Updating.downloading;
    downloaded = 0;
    updateProblem = null;
    notifyListeners();
    try {
      final folder = Directory(await phone.updatesFolder());
      final file = await downloadApk(client, release, folder, (d) {
        downloaded = d;
        notifyListeners();
      });
      final why = await phone.install(file.path);
      if (why == null) {
        updating = Updating.handed;
      } else {
        updating = Updating.failed;
        updateProblem = why;
      }
    } on UpdateError catch (e) {
      updating = Updating.failed;
      updateProblem = e.message;
    } catch (e) {
      updating = Updating.failed;
      updateProblem = 'The update could not be downloaded ($e).';
    }
    notifyListeners();
  }
}
