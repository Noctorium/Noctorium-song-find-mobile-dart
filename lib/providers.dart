/// Who is asked what the song is.
///
/// - **Shazam**, through the same fingerprint its own apps send. Needs nothing set up. Not an official,
///   documented service, so it may change.
/// - **AudD** (audd.io), sent a few seconds of the sound. A few tries a day without a token; a token lifts it.
/// - **ACRCloud**, sent the sound and signed with a project's access key and secret (console.acrcloud.com).
///
/// Asked in the order Settings gives, until one knows the song -- or every one, if Settings says so.
/// (AcoustID, which the desktop also asks, wants a Chromaprint fingerprint of a whole song from a file, so
/// it is the desktop's alone.)
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'signature.dart';
import 'song.dart';

enum Provider {
  shazam('Shazam', 'Knows the most songs. Needs nothing set up. Only a fingerprint is sent, never the sound.'),
  audd('AudD', 'Sent a few seconds of the sound. A few tries a day without a token; a token from audd.io lifts that.'),
  acrcloud(
    'ACRCloud',
    "Sent a few seconds of the sound. Needs a project's host, access key and secret, free at console.acrcloud.com.",
  );

  const Provider(this.label, this.about);

  final String label;
  final String about;
}

/// What the providers need from Settings.
class Keys {
  const Keys({this.auddToken = '', this.acrHost = '', this.acrKey = '', this.acrSecret = ''});

  final String auddToken;
  final String acrHost;
  final String acrKey;
  final String acrSecret;

  /// Null when [provider] can be asked; why not, otherwise.
  String? missing(Provider provider) => switch (provider) {
    Provider.acrcloud when acrHost.trim().isEmpty || acrKey.trim().isEmpty || acrSecret.trim().isEmpty =>
      'needs a host, access key and secret in Settings',
    _ => null,
  };
}

sealed class Answer {
  const Answer();
}

class Found extends Answer {
  const Found(this.song);
  final Song song;
}

class Unknown extends Answer {
  const Unknown();
}

class Failed extends Answer {
  const Failed(this.why);
  final String why;
}

/// 16 kHz mono samples.
class Clip {
  Clip(this.samples);

  /// From the little-endian 16-bit bytes Android records. Read through ByteData rather than viewed: the
  /// bytes a platform channel hands over can start at an odd offset, which a 16-bit view cannot.
  factory Clip.fromPcm(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final samples = Int16List(bytes.lengthInBytes ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little);
    }
    return Clip(samples);
  }

  final Int16List samples;

  double get seconds => samples.length / sampleRate;

  /// How loud its loudest tenth of a second is, from 0 to 1.
  double get level {
    var best = 0.0;
    for (var start = 0; start < samples.length; start += 1600) {
      final end = math.min(start + 1600, samples.length);
      var sum = 0.0;
      for (var i = start; i < end; i++) {
        final v = samples[i] / 32768;
        sum += v * v;
      }
      best = math.max(best, math.sqrt(sum / (end - start)));
    }
    return best;
  }

  Uint8List wav({int mostSeconds = 12}) {
    final count = math.min(samples.length, sampleRate * mostSeconds);
    final data = count * 2;
    final out = ByteData(44 + data);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    out.setUint32(4, 36 + data, Endian.little);
    ascii(8, 'WAVEfmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, 1, Endian.little);
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 2, Endian.little);
    out.setUint16(32, 2, Endian.little);
    out.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    out.setUint32(40, data, Endian.little);
    for (var i = 0; i < count; i++) {
      out.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return out.buffer.asUint8List();
  }
}

class Providers {
  Providers(this._client, {this.version = '0.0.0'});

  final http.Client _client;
  final String version;
  final _random = math.Random.secure();

  Future<Answer> ask(Provider provider, Clip clip, Keys keys) async {
    final missing = keys.missing(provider);
    if (missing != null) return Failed('${provider.label} $missing.');
    try {
      final song = await switch (provider) {
        Provider.shazam => shazam(clip),
        Provider.audd => audd(clip, keys.auddToken),
        Provider.acrcloud => acrcloud(clip, keys),
      }.timeout(const Duration(seconds: 25));
      return song == null ? const Unknown() : Found(song.withProvider(provider.label));
    } on ProviderError catch (e) {
      return Failed('${provider.label}: ${e.message}');
    } catch (e) {
      return Failed('${provider.label}: could not reach it ($e)');
    }
  }

  // ------------------------------------------------------------------------------------------- Shazam

  static const _userAgents = [
    'Dalvik/2.1.0 (Linux; U; Android 5.0.2; VS980 4G Build/LRX22G)',
    'Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G920F Build/MMB29K)',
    'Dalvik/2.1.0 (Linux; U; Android 7.0; SM-G930F Build/NRD90M)',
    'Dalvik/2.1.0 (Linux; U; Android 8.0.0; SM-G950F Build/R16NW)',
    'Dalvik/2.1.0 (Linux; U; Android 9; SM-G960F Build/PPR1.180610.011)',
    'Dalvik/2.1.0 (Linux; U; Android 10; Pixel 3 Build/QQ3A.200805.001)',
  ];

  String _uuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<Song?> shazam(Clip clip) async {
    final signature = SignatureGenerator.of(clip.samples);
    if (signature.peakCount == 0) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse('https://amp.shazam.com/discovery/v5/en/US/android/-/tag/${_uuid()}/${_uuid()}').replace(
      queryParameters: const {
        'sync': 'true',
        'webv3': 'true',
        'sampling': 'true',
        'connected': '',
        'shazamapiversion': 'v3',
        'sharehub': 'true',
        'video': 'v3',
      },
    );
    final response = await _client.post(
      url,
      headers: {
        'User-Agent': _userAgents[_random.nextInt(_userAgents.length)],
        'Content-Language': 'en_US',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'geolocation': {'altitude': 300, 'latitude': 45, 'longitude': 2},
        'signature': {'samplems': signature.milliseconds, 'timestamp': now, 'uri': signature.uri},
        'timestamp': now,
        'timezone': 'Europe/Paris',
      }),
    );
    _checkStatus(response);
    return readShazam(jsonDecode(response.body));
  }

  static Song? readShazam(Object? reply) {
    final matches = dig(reply, ['matches']);
    final track = dig(reply, ['track']);
    if (matches is! List || matches.isEmpty || track is! Map) return null;
    final title = text(track['title']);
    if (title == null) return null;
    String? album, year, label;
    for (final section in (track['sections'] as List?) ?? const []) {
      for (final item in (dig(section, ['metadata']) as List?) ?? const []) {
        final value = text(dig(item, ['text']));
        switch (dig(item, ['title'])) {
          case 'Album':
            album ??= value;
          case 'Released':
            year ??= value;
          case 'Label':
            label ??= value;
        }
      }
    }
    String? apple, spotify, deezer, youtube;
    final all = <String>[];
    strings(track['hub'], all);
    for (final link in all) {
      if (link.startsWith('https://music.apple.com/')) {
        apple ??= link;
      } else if (link.startsWith('spotify:track:')) {
        spotify ??= 'https://open.spotify.com/track/${link.substring('spotify:track:'.length)}';
      } else if (link.startsWith('https://open.spotify.com/track/')) {
        spotify ??= link;
      } else if (link.startsWith('https://www.deezer.com/track/')) {
        deezer ??= link;
      } else if (link.startsWith('https://www.youtube.com/watch') || link.startsWith('https://youtu.be/')) {
        youtube ??= link;
      }
    }
    return Song(
      title: title,
      artist: text(track['subtitle']) ?? '',
      album: album,
      year: year,
      label: label,
      genre: text(dig(track, ['genres', 'primary'])),
      isrc: text(track['isrc']),
      cover: text(dig(track, ['images', 'coverarthq'])) ?? text(dig(track, ['images', 'coverart'])),
      page: text(track['url']),
      spotify: spotify,
      appleMusic: apple,
      deezer: deezer,
      youtube: youtube,
    );
  }

  // --------------------------------------------------------------------------------------------- AudD

  Future<Song?> audd(Clip clip, String token) async {
    final request = http.MultipartRequest('POST', Uri.parse('https://api.audd.io/'))
      ..fields['return'] = 'apple_music,spotify,deezer'
      ..files.add(http.MultipartFile.fromBytes('file', clip.wav(), filename: 'clip.wav'));
    if (token.trim().isNotEmpty) request.fields['api_token'] = token.trim();
    request.headers['User-Agent'] = 'NoctoriumSongFind/$version';
    final response = await http.Response.fromStream(await _client.send(request));
    _checkStatus(response);
    return readAudd(jsonDecode(response.body));
  }

  static Song? readAudd(Object? reply) {
    if (dig(reply, ['status']) == 'error') {
      throw ProviderError(text(dig(reply, ['error', 'error_message'])) ?? 'an error');
    }
    final result = dig(reply, ['result']);
    if (result is! Map) return null;
    final title = text(result['title']);
    if (title == null) return null;
    final apple = result['apple_music'];
    final spotify = result['spotify'];
    final deezer = result['deezer'];
    return Song(
      title: title,
      artist: text(result['artist']) ?? '',
      album: text(result['album']),
      year: text(result['release_date'])?.split('-').first,
      label: text(result['label']),
      genre: text(dig(apple, ['genreNames', 0])),
      isrc: text(dig(apple, ['isrc'])) ?? text(dig(spotify, ['external_ids', 'isrc'])),
      cover:
          text(dig(apple, ['artwork', 'url']))?.replaceAll('{w}', '600').replaceAll('{h}', '600') ??
          text(dig(spotify, ['album', 'images', 0, 'url'])) ??
          text(dig(deezer, ['album', 'cover_xl'])),
      page: text(result['song_link']),
      spotify: text(dig(spotify, ['external_urls', 'spotify'])),
      appleMusic: text(dig(apple, ['url'])),
      deezer: text(dig(deezer, ['link'])),
    );
  }

  // ----------------------------------------------------------------------------------------- ACRCloud

  static String acrSignature(String key, String secret, int timestamp) {
    final toSign = 'POST\n/v1/identify\n$key\naudio\n1\n$timestamp';
    return base64.encode(Hmac(sha1, utf8.encode(secret)).convert(utf8.encode(toSign)).bytes);
  }

  Future<Song?> acrcloud(Clip clip, Keys keys) async {
    final host = keys.acrHost.trim().replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    final key = keys.acrKey.trim();
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final wav = clip.wav();
    final request = http.MultipartRequest('POST', Uri.parse('https://$host/v1/identify'))
      ..fields.addAll({
        'access_key': key,
        'data_type': 'audio',
        'signature_version': '1',
        'signature': acrSignature(key, keys.acrSecret.trim(), timestamp),
        'sample_bytes': '${wav.length}',
        'timestamp': '$timestamp',
      })
      ..files.add(http.MultipartFile.fromBytes('sample', wav, filename: 'clip.wav'));
    final response = await http.Response.fromStream(await _client.send(request));
    _checkStatus(response);
    return readAcrcloud(jsonDecode(response.body));
  }

  static Song? readAcrcloud(Object? reply) {
    final code = dig(reply, ['status', 'code']);
    if (code == 1001) return null;
    if (code != 0) throw ProviderError(text(dig(reply, ['status', 'msg'])) ?? 'an unexpected answer');
    final music = dig(reply, ['metadata', 'music', 0]);
    final title = text(dig(music, ['title']));
    if (title == null) return null;
    final artists = [
      for (final a in (dig(music, ['artists']) as List?) ?? const []) ?text(dig(a, ['name'])),
    ];
    final spotify = text(dig(music, ['external_metadata', 'spotify', 'track', 'id']));
    final deezer = dig(music, ['external_metadata', 'deezer', 'track', 'id']);
    final youtube = text(dig(music, ['external_metadata', 'youtube', 'vid']));
    return Song(
      title: title,
      artist: artists.join(', '),
      album: text(dig(music, ['album', 'name'])),
      year: text(dig(music, ['release_date']))?.split('-').first,
      label: text(dig(music, ['label'])),
      genre: text(dig(music, ['genres', 0, 'name'])),
      isrc: text(dig(music, ['external_ids', 'isrc'])),
      spotify: spotify == null ? null : 'https://open.spotify.com/track/$spotify',
      deezer: deezer == null ? null : 'https://www.deezer.com/track/$deezer',
      youtube: youtube == null ? null : 'https://www.youtube.com/watch?v=$youtube',
    );
  }

  static void _checkStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
    throw ProviderError('the service answered ${response.statusCode} ${body.trim()}');
  }
}

class ProviderError implements Exception {
  ProviderError(this.message);
  final String message;

  @override
  String toString() => message;
}
