import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_song_find/providers.dart';
import 'package:noctorium_song_find/store.dart';
import 'package:noctorium_song_find/update.dart';

import 'support.dart';

void main() {
  test('the answer from Shazam is read', () {
    final song = Providers.readShazam(shazamMatch)!;
    expect(song.title, 'Never Gonna Give You Up');
    expect(song.artist, 'Rick Astley');
    expect(song.album, 'Whenever You Need Somebody');
    expect(song.year, '1987');
    expect(song.spotify, 'https://open.spotify.com/track/4PTG3Z6ehGkBFwjybzWkR8');
    expect(Providers.readShazam({'matches': [], 'retryms': 12000}), isNull);
  });

  test('the answer from AudD, and its errors, are read', () {
    final song = Providers.readAudd({
      'status': 'success',
      'result': {
        'artist': 'Imagine Dragons',
        'title': 'Warriors',
        'release_date': '2014-09-18',
        'apple_music': {
          'url': 'https://music.apple.com/x',
          'artwork': {'url': 'https://a/{w}x{h}bb.jpg'},
        },
      },
    })!;
    expect(song.year, '2014');
    expect(song.cover, 'https://a/600x600bb.jpg');
    expect(Providers.readAudd({'status': 'success', 'result': null}), isNull);
    expect(
      () => Providers.readAudd({
        'status': 'error',
        'error': {'error_message': 'limit reached'},
      }),
      throwsA(isA<ProviderError>()),
    );
  });

  test('the answer from ACRCloud, no result, and errors', () {
    final song = Providers.readAcrcloud({
      'status': {'code': 0, 'msg': 'Success'},
      'metadata': {
        'music': [
          {
            'title': 'Numb',
            'artists': [
              {'name': 'Linkin Park'},
            ],
            'external_metadata': {
              'deezer': {
                'track': {'id': 2475381},
              },
              'youtube': {'vid': 'kXYiU_JCYtU'},
            },
          },
        ],
      },
    })!;
    expect(song.artist, 'Linkin Park');
    expect(song.deezer, 'https://www.deezer.com/track/2475381');
    expect(song.youtube, 'https://www.youtube.com/watch?v=kXYiU_JCYtU');
    expect(
      Providers.readAcrcloud({
        'status': {'code': 1001, 'msg': 'No result'},
      }),
      isNull,
    );
    expect(
      () => Providers.readAcrcloud({
        'status': {'code': 3001, 'msg': 'invalid key'},
      }),
      throwsA(isA<ProviderError>()),
    );
    expect(Providers.acrSignature('key', 'secret', 1700000000).length, 28);
  });

  test('providers that need keys say so', () {
    const keys = Keys();
    expect(keys.missing(Provider.shazam), isNull);
    expect(keys.missing(Provider.audd), isNull);
    expect(keys.missing(Provider.acrcloud), isNotNull);
  });

  test('PCM at an odd offset is read, little-endian', () {
    final backing = Uint8List.fromList([9, 0x34, 0x12, 0xff, 0xff, 7]);
    final clip = Clip.fromPcm(Uint8List.sublistView(backing, 1, 5));
    expect(clip.samples, [0x1234, -1]);
  });

  test('a clip becomes a WAV', () {
    final clip = Clip(tune(3));
    final wav = clip.wav(mostSeconds: 2);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.length, 44 + 16000 * 2 * 2);
    expect(clip.level, greaterThan(.02));
  });

  test('settings survive being written and read back, and odd ones are tidied', () {
    final settings = Settings(
      source: Source.system,
      seconds: 15,
      providers: [(Provider.audd, false), (Provider.audd, true)],
      keys: const Keys(auddToken: 't'),
    );
    expect(settings.providers.length, 3);
    expect(settings.providers.first, (Provider.audd, false));
    final back = Settings.fromJson(settings.toJson());
    expect(back.source, Source.system);
    expect(back.seconds, 15);
    expect(back.keys.auddToken, 't');
    expect(back.inOrder, [Provider.shazam, Provider.acrcloud]);
  });

  test("a release's APK and its checksum are found", () {
    final release = Release.fromJson('''{
      "tag_name": "v0.28.0", "html_url": "https://github.com/x",
      "assets": [
        {"name": "Noctorium-0.28.0.apk", "browser_download_url": "https://x/a.apk", "digest": "sha256:aa"},
        {"name": "Noctorium-Song-Find-0.28.0.apk", "browser_download_url": "https://x/b.apk", "digest": "sha256:BB"}
      ]}''')!;
    expect(release.version.toString(), '0.28.0');
    expect(release.apk.toString(), 'https://x/b.apk');
    expect(release.sha256, 'bb');
  });
}
