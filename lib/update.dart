/// Whether a newer Noctorium Song Find is out, and getting it.
///
/// Song Find ships in every Noctorium release, so the newest release of Noctorium-Installer is the newest
/// Song Find. Asked once at launch; a check that fails for any reason -- offline, GitHub's rate limit --
/// says nothing at all. Installing it downloads the release's `Noctorium-Song-Find-<version>.apk`, checks it
/// against the SHA-256 GitHub publishes for it, and hands it to Android's own installer, which asks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const String latestReleaseApi = 'https://api.github.com/repos/Noctorium/Noctorium-Installer/releases/latest';

/// A version as the release tags write it: `v0.12.2`, `0.13.0`, `v1.0.0-beta.1`.
class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch, {this.preRelease = ''});

  final int major;
  final int minor;
  final int patch;

  /// What follows a hyphen, which sorts before the same version without one.
  final String preRelease;

  static Version? parse(String? text) {
    if (text == null) return null;
    final match = RegExp(r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$').firstMatch(text.trim());
    if (match == null) return null;
    return Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2) ?? '0'),
      int.parse(match.group(3) ?? '0'),
      preRelease: match.group(4) ?? '',
    );
  }

  /// Android's versionCode for this version, packed as Noctorium's is: 1.2.3 is 10203.
  int get versionCode => major * 10000 + minor * 100 + patch;

  @override
  int compareTo(Version other) {
    for (final (a, b) in [(major, other.major), (minor, other.minor), (patch, other.patch)]) {
      if (a != b) return a.compareTo(b);
    }
    if (preRelease == other.preRelease) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    return preRelease.compareTo(other.preRelease);
  }

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() => '$major.$minor.$patch${preRelease.isEmpty ? '' : '-$preRelease'}';
}

class Release {
  const Release({required this.version, required this.page, this.apk, this.sha256});

  final Version version;

  /// The release's page on GitHub, which is where somebody goes to get it.
  final Uri page;

  /// Song Find's APK in the release, and the SHA-256 GitHub gives for it, when it has them.
  final Uri? apk;
  final String? sha256;

  /// Reads GitHub's answer for a release; null for anything that is not one.
  static Release? fromJson(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final version = Version.parse(json['tag_name'] as String?);
      final page = Uri.tryParse(json['html_url'] as String? ?? '');
      if (version == null || page == null || !page.hasScheme) return null;
      Uri? apk;
      String? sha256;
      for (final asset in (json['assets'] as List?) ?? const []) {
        if (asset is! Map) continue;
        final name = asset['name'] as String? ?? '';
        if (name.startsWith('Noctorium-Song-Find-') && name.endsWith('.apk')) {
          apk = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
          final digest = asset['digest'] as String? ?? '';
          sha256 = digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null;
        }
      }
      return Release(version: version, page: page, apk: apk, sha256: sha256);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class UpdateChecker {
  UpdateChecker(this._client, {this.url = latestReleaseApi});

  final http.Client _client;
  final String url;

  /// The latest release when it is newer than [current]; null when it is not, or when nobody could say.
  Future<Release?> newerThan(String current) async {
    final installed = Version.parse(current);
    if (installed == null) return null;
    try {
      final response = await _client
          .get(Uri.parse(url), headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final release = Release.fromJson(response.body);
      return release != null && release.version > installed ? release : null;
    } catch (_) {
      return null;
    }
  }
}

/// Downloads [release]'s APK into [folder] and checks it, telling [progress] how far along it is. Returns the
/// file; throws with a sentence to show when it cannot.
Future<File> downloadApk(http.Client client, Release release, Directory folder, void Function(double) progress) async {
  final url = release.apk;
  final expected = release.sha256;
  if (url == null || expected == null) {
    throw const UpdateError('This release cannot be checked, so it is not installed from here. Get it from its page.');
  }
  final response = await client.send(http.Request('GET', url));
  if (response.statusCode != 200) throw UpdateError('The download failed (${response.statusCode}).');
  await folder.create(recursive: true);
  for (final old in folder.listSync()) {
    if (old is File) await old.delete();
  }
  final file = File('${folder.path}/Noctorium-Song-Find-${release.version}.apk');
  final sink = file.openWrite();
  final total = response.contentLength ?? 0;
  var got = 0;
  final digest = AccumulatorSink<Digest>();
  final hashing = sha256.startChunkedConversion(digest);
  await for (final chunk in response.stream) {
    sink.add(chunk);
    hashing.add(chunk);
    got += chunk.length;
    if (total > 0) progress(got / total);
  }
  await sink.close();
  hashing.close();
  if (digest.events.single.toString() != expected) {
    await file.delete();
    throw const UpdateError('The download did not match the checksum the release publishes, so it was not used.');
  }
  return file;
}

class UpdateError implements Exception {
  const UpdateError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Collects what a chunked hash produces.
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
