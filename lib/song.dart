/// A song that was found, whoever found it, and where it can be listened to.
library;

class Song {
  const Song({
    required this.title,
    required this.artist,
    this.album,
    this.year,
    this.label,
    this.genre,
    this.isrc,
    this.cover,
    this.page,
    this.spotify,
    this.appleMusic,
    this.deezer,
    this.youtube,
    this.provider = '',
  });

  final String title;
  final String artist;
  final String? album;
  final String? year;
  final String? label;
  final String? genre;
  final String? isrc;
  final String? cover;
  final String? page;
  final String? spotify;
  final String? appleMusic;
  final String? deezer;
  final String? youtube;
  final String provider;

  Song withProvider(String name) => Song(
    title: title,
    artist: artist,
    album: album,
    year: year,
    label: label,
    genre: genre,
    isrc: isrc,
    cover: cover,
    page: page,
    spotify: spotify,
    appleMusic: appleMusic,
    deezer: deezer,
    youtube: youtube,
    provider: name,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'album': album,
    'year': year,
    'label': label,
    'genre': genre,
    'isrc': isrc,
    'cover': cover,
    'page': page,
    'spotify': spotify,
    'apple_music': appleMusic,
    'deezer': deezer,
    'youtube': youtube,
    'provider': provider,
  };

  static Song fromJson(Map<String, dynamic> json) => Song(
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    album: json['album'] as String?,
    year: json['year'] as String?,
    label: json['label'] as String?,
    genre: json['genre'] as String?,
    isrc: json['isrc'] as String?,
    cover: json['cover'] as String?,
    page: json['page'] as String?,
    spotify: json['spotify'] as String?,
    appleMusic: json['apple_music'] as String?,
    deezer: json['deezer'] as String?,
    youtube: json['youtube'] as String?,
    provider: json['provider'] as String? ?? '',
  );

  /// Where it can be heard, as (name, address): the provider's own links first, then searches.
  List<(String, String)> get links {
    final q = Uri.encodeComponent('$artist $title');
    return [
      ('Spotify', spotify ?? 'https://open.spotify.com/search/$q'),
      ('YouTube Music', youtube ?? 'https://music.youtube.com/search?q=$q'),
      ('Apple Music', appleMusic ?? 'https://music.apple.com/search?term=$q'),
      ('Deezer', deezer ?? 'https://www.deezer.com/search/$q'),
      ('SoundCloud', 'https://soundcloud.com/search?q=$q'),
      ('Lyrics', 'https://www.google.com/search?q=${Uri.encodeComponent('$artist $title lyrics')}'),
      if (page != null) ("Provider's page", page!),
    ];
  }
}

/// A non-empty, trimmed string, or null.
String? text(Object? value) {
  if (value is! String) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

/// Every string anywhere in decoded JSON, for picking links out of answers whose shape varies.
void strings(Object? value, List<String> out) {
  if (value is String) {
    out.add(value);
  } else if (value is List) {
    for (final v in value) {
      strings(v, out);
    }
  } else if (value is Map) {
    for (final v in value.values) {
      strings(v, out);
    }
  }
}

/// value[a][b][c]..., null wherever the shape is not as expected.
Object? dig(Object? value, List<Object> path) {
  var at = value;
  for (final key in path) {
    if (key is String && at is Map) {
      at = at[key];
    } else if (key is int && at is List && key < at.length) {
      at = at[key];
    } else {
      return null;
    }
  }
  return at;
}
