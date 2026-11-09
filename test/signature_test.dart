import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_song_find/signature.dart';

import 'support.dart';

void main() {
  test('silence has no peaks', () {
    final s = SignatureGenerator.of(Int16List(16000 * 5));
    expect(s.peakCount, 0);
    expect(s.samples, 16000 * 5);
  });

  test('a tune has peaks in its bands, in order', () {
    final s = SignatureGenerator.of(tune(6));
    expect(s.peakCount, greaterThan(20));
    expect(s.bands.where((b) => b.isNotEmpty).length, greaterThanOrEqualTo(3));
    for (final band in s.bands) {
      for (var i = 1; i < band.length; i++) {
        expect(band[i].pass, greaterThanOrEqualTo(band[i - 1].pass));
      }
    }
  });

  test('the binary is shaped as Shazam reads it', () {
    final bytes = SignatureGenerator.of(tune(4)).encode();
    final view = ByteData.sublistView(bytes);
    int word(int at) => view.getUint32(at, Endian.little);
    expect(word(0), 0xcafe2580);
    expect(word(12), 0x94119c00);
    expect(word(8), bytes.length - 48);
    expect(word(52), word(8));
    expect(word(4), crc32(bytes.sublist(8)));
    expect(bytes.length % 4, 0);
  });

  test('only twelve seconds are used', () {
    final s = SignatureGenerator.of(Int16List(16000 * 30));
    expect(s.samples, 16000 * 12);
    expect(s.milliseconds, 12000);
  });

  test('CRC-32 is the standard one', () {
    expect(crc32('123456789'.codeUnits), 0xcbf43926);
  });

  test('the FFT finds a tone in its bin', () {
    final re = Float64List(2048);
    final im = Float64List(2048);
    for (var i = 0; i < 2048; i++) {
      re[i] = i % 8 < 4 ? 1 : -1; // a square wave of period 8: bin 256
    }
    fft(re, im);
    double power(int i) => re[i] * re[i] + im[i] * im[i];
    var best = 1;
    for (var i = 1; i < 1024; i++) {
      if (power(i) > power(best)) best = i;
    }
    expect(best, 256);
  });
}
