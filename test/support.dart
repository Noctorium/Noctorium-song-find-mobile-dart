import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noctorium_song_find/audio.dart';
import 'package:noctorium_song_find/providers.dart';
import 'package:noctorium_song_find/store.dart';

/// A chord that moves, so there are peaks to find in more than one place and time.
Int16List tune(int seconds) {
  const notes = [440.0, 554.37, 659.25, 880.0, 1174.66, 2349.3, 4186.0];
  final out = Int16List(16000 * seconds);
  for (var i = 0; i < out.length; i++) {
    final t = i / 16000;
    final step = (t * 4).floor();
    var v = 0.0;
    for (var n = 0; n < notes.length; n++) {
      if ((step + n) % 3 != 0) v += math.sin(2 * math.pi * notes[n] * t) / notes.length;
    }
    out[i] = (v * 20000).truncate();
  }
  return out;
}

class FakePhone implements Phone {
  FakePhone({this.clip, this.error});

  Clip? clip;
  String? error;
  String? installed;

  @override
  Future<Clip> record(Source source, int seconds, void Function(double, double) progress) async {
    progress(.5, .5);
    if (error != null) throw ListenError(error!);
    return clip ?? Clip(tune(6));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<bool> systemAudioSupported() async => true;

  @override
  Future<String> updatesFolder() async => '/nowhere';

  @override
  Future<String?> install(String path) async {
    installed = path;
    return null;
  }
}

const shazamMatch = {
  'matches': [
    {'id': '1'},
  ],
  'track': {
    'title': 'Never Gonna Give You Up',
    'subtitle': 'Rick Astley',
    'url': 'https://www.shazam.com/track/357027/never-gonna-give-you-up',
    'sections': [
      {
        'type': 'SONG',
        'metadata': [
          {'title': 'Album', 'text': 'Whenever You Need Somebody'},
          {'title': 'Released', 'text': '1987'},
        ],
      },
    ],
    'hub': {
      'providers': [
        {
          'actions': [
            {'uri': 'spotify:track:4PTG3Z6ehGkBFwjybzWkR8'},
          ],
        },
      ],
    },
  },
};

/// Shazam answers with [shazam], GitHub has nothing newer, and anything else is a 404.
http.Client fakeNetwork({Object shazam = shazamMatch}) => MockClient((request) async {
  if (request.url.host == 'amp.shazam.com') return http.Response(jsonEncode(shazam), 200);
  if (request.url.host == 'api.github.com') {
    return http.Response(jsonEncode({'tag_name': 'v0.0.1', 'html_url': 'https://github.com/x'}), 200);
  }
  return http.Response('nope', 404);
});
