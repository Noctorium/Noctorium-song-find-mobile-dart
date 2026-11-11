/// What is kept on the phone: the settings, and the history of songs found. Never sent anywhere.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';
import 'song.dart';

enum Source { microphone, system }

class Settings {
  Settings({
    this.source = Source.microphone,
    this.seconds = 10,
    List<(Provider, bool)>? providers,
    this.askEveryone = false,
    this.keepHistory = true,
    this.keys = const Keys(),
    this.checkForUpdates = true,
    this.notifyWhenDone = true,
  }) : providers = tidy(providers ?? [for (final p in Provider.values) (p, true)]);

  final Source source;
  final int seconds;
  final List<(Provider, bool)> providers;
  final bool askEveryone;
  final bool keepHistory;
  final Keys keys;
  final bool checkForUpdates;

  /// A notification when a search ends while Song Find is not on screen.
  final bool notifyWhenDone;

  static const lengths = [5, 8, 10, 15];

  /// Every provider once, in the order given, any missing ones at the end.
  static List<(Provider, bool)> tidy(List<(Provider, bool)> list) {
    final seen = <Provider>{};
    final out = [
      for (final entry in list)
        if (seen.add(entry.$1)) entry,
    ];
    for (final p in Provider.values) {
      if (seen.add(p)) out.add((p, true));
    }
    return out;
  }

  List<Provider> get inOrder => [
    for (final (p, on) in providers)
      if (on) p,
  ];

  Settings copyWith({
    Source? source,
    int? seconds,
    List<(Provider, bool)>? providers,
    bool? askEveryone,
    bool? keepHistory,
    Keys? keys,
    bool? checkForUpdates,
    bool? notifyWhenDone,
  }) => Settings(
    source: source ?? this.source,
    seconds: seconds ?? this.seconds,
    providers: providers ?? this.providers,
    askEveryone: askEveryone ?? this.askEveryone,
    keepHistory: keepHistory ?? this.keepHistory,
    keys: keys ?? this.keys,
    checkForUpdates: checkForUpdates ?? this.checkForUpdates,
    notifyWhenDone: notifyWhenDone ?? this.notifyWhenDone,
  );

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'seconds': seconds,
    'providers': [
      for (final (p, on) in providers) {'name': p.name, 'on': on},
    ],
    'ask_everyone': askEveryone,
    'keep_history': keepHistory,
    'audd_token': keys.auddToken,
    'acrcloud_host': keys.acrHost,
    'acrcloud_key': keys.acrKey,
    'acrcloud_secret': keys.acrSecret,
    'check_for_updates': checkForUpdates,
    'notify_when_done': notifyWhenDone,
  };

  static Settings fromJson(Map<String, dynamic> json) {
    final providers = <(Provider, bool)>[];
    for (final entry in (json['providers'] as List?) ?? const []) {
      if (entry is! Map) continue;
      final p = Provider.values.where((p) => p.name == entry['name']).firstOrNull;
      if (p != null) providers.add((p, entry['on'] != false));
    }
    final seconds = json['seconds'];
    return Settings(
      source: json['source'] == 'system' ? Source.system : Source.microphone,
      seconds: seconds is int ? seconds.clamp(3, 20) : 10,
      providers: providers.isEmpty ? null : providers,
      askEveryone: json['ask_everyone'] == true,
      keepHistory: json['keep_history'] != false,
      keys: Keys(
        auddToken: json['audd_token'] as String? ?? '',
        acrHost: json['acrcloud_host'] as String? ?? '',
        acrKey: json['acrcloud_key'] as String? ?? '',
        acrSecret: json['acrcloud_secret'] as String? ?? '',
      ),
      checkForUpdates: json['check_for_updates'] != false,
      notifyWhenDone: json['notify_when_done'] != false,
    );
  }
}

/// A song found, when, and how it was heard.
class Entry {
  const Entry(this.song, this.at, this.source);

  final Song song;
  final DateTime at;
  final String source;

  Map<String, dynamic> toJson() => {'song': song.toJson(), 'at': at.toUtc().toIso8601String(), 'source': source};

  static Entry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final song = json['song'];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (song is! Map<String, dynamic> || at == null) return null;
    return Entry(Song.fromJson(song), at, json['source'] as String? ?? '');
  }
}

const historyMost = 500;

class Store {
  Store(this._prefs);

  final SharedPreferences _prefs;

  static Future<Store> open() async => Store(await SharedPreferences.getInstance());

  Settings get settings {
    try {
      final raw = _prefs.getString('settings');
      return raw == null ? Settings() : Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Settings();
    }
  }

  Future<void> saveSettings(Settings settings) => _prefs.setString('settings', jsonEncode(settings.toJson()));

  List<Entry> get history {
    try {
      final raw = _prefs.getString('history');
      if (raw == null) return [];
      return [for (final e in jsonDecode(raw) as List) ?Entry.fromJson(e)];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<Entry> history) =>
      _prefs.setString('history', jsonEncode([for (final e in history.take(historyMost)) e.toJson()]));
}
