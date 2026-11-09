/// The fingerprint Shazam reads: peaks of the sound's spectrum, found and written the way its own apps do.
///
/// The same algorithm as the desktop's (signature.rs), which is the one SongRec (GPL-3.0, like Noctorium)
/// worked out from Shazam's Android app: the sound at 16 kHz in one channel, a 2048-point FFT every 128
/// samples under a Hann window, each spectrum spread over its neighbours in frequency and in time, and the
/// points that stand out from everything around them kept as peaks, in four bands. Only the fingerprint is
/// ever sent, never the sound.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 16000;

/// What Shazam needs to be sure, and no more is sent.
const int maxSeconds = 12;

class Peak {
  const Peak(this.pass, this.magnitude, this.bin);

  final int pass;
  final int magnitude;
  final int bin;

  @override
  bool operator ==(Object other) =>
      other is Peak && other.pass == pass && other.magnitude == magnitude && other.bin == bin;

  @override
  int get hashCode => Object.hash(pass, magnitude, bin);
}

class Signature {
  Signature(this.samples, this.bands);

  final int samples;

  /// 250-520 Hz, 520-1450, 1450-3500 and 3500-5500.
  final List<List<Peak>> bands;

  int get peakCount => bands.fold(0, (sum, b) => sum + b.length);

  int get milliseconds => samples * 1000 ~/ sampleRate;

  /// The signature in Shazam's binary format.
  Uint8List encode() {
    final out = BytesBuilder();
    void word(int v) => out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    word(0xcafe2580);
    word(0); // the CRC, written last
    word(0); // the size, written last
    word(0x94119c00);
    word(0);
    word(0);
    word(0);
    word(3 << 27); // 16 kHz, as Shazam numbers sample rates
    word(0);
    word(0);
    word(samples + (sampleRate * 0.24).toInt());
    word((15 << 19) + 0x40000);
    word(0x40000000);
    word(0); // the size again

    for (var band = 0; band < bands.length; band++) {
      final peaks = bands[band];
      if (peaks.isEmpty) continue;
      final packed = BytesBuilder();
      var pass = 0;
      for (final peak in peaks) {
        if (peak.pass - pass >= 255) {
          packed.addByte(0xff);
          packed.add((ByteData(4)..setUint32(0, peak.pass, Endian.little)).buffer.asUint8List());
          pass = peak.pass;
        }
        packed.addByte(peak.pass - pass);
        packed.add((ByteData(2)..setUint16(0, peak.magnitude, Endian.little)).buffer.asUint8List());
        packed.add((ByteData(2)..setUint16(0, peak.bin, Endian.little)).buffer.asUint8List());
        pass = peak.pass;
      }
      word(0x60030040 + band);
      word(packed.length);
      out.add(packed.takeBytes());
      while (out.length % 4 != 0) {
        out.addByte(0);
      }
    }

    final bytes = out.takeBytes();
    final view = ByteData.sublistView(bytes);
    final size = bytes.length - 48;
    view.setUint32(8, size, Endian.little);
    view.setUint32(52, size, Endian.little);
    view.setUint32(4, crc32(Uint8List.sublistView(bytes, 8)), Endian.little);
    return bytes;
  }

  String get uri => 'data:audio/vnd.shazam.sig;base64,${base64.encode(encode())}';
}

const int _fftSize = 2048;
const int _bins = _fftSize ~/ 2 + 1;
const int _history = 256;

/// Works through 16 kHz mono samples 128 at a time.
class SignatureGenerator {
  SignatureGenerator() {
    for (var i = 0; i < _fftSize; i++) {
      _window[i] = .5 - .5 * math.cos(2 * math.pi * (i + 1) / (_fftSize + 1));
    }
    for (var i = 0; i < _history; i++) {
      _spectra.add(Float32List(_bins));
      _spread.add(Float32List(_bins));
    }
  }

  final _window = Float64List(_fftSize);
  final _ring = Int16List(_fftSize);
  var _ringAt = 0;
  final _spectra = <Float32List>[];
  var _spectraAt = 0;
  final _spread = <Float32List>[];
  var _spreadAt = 0;
  var _spreadWritten = 0;
  final _re = Float64List(_fftSize);
  final _im = Float64List(_fftSize);
  final _pending = <int>[];
  var _samples = 0;
  final _bands = List.generate(4, (_) => <Peak>[]);

  /// The whole of a recording at once. Only the first [maxSeconds] are used.
  static Signature of(Int16List samples) {
    final generator = SignatureGenerator();
    generator.feed(samples.length > sampleRate * maxSeconds ? samples.sublist(0, sampleRate * maxSeconds) : samples);
    return generator.finish();
  }

  void feed(List<int> samples) {
    for (final s in samples) {
      _pending.add(s);
      if (_pending.length == 128) {
        _process(_pending);
        _pending.clear();
      }
    }
  }

  Signature finish() => Signature(_samples, _bands);

  static int _back(int at, int by) => (at + by) % _history;

  void _process(List<int> chunk) {
    _samples += chunk.length;
    _fft(chunk);
    _spreadPeaks();
    if (_spreadWritten >= 46) _recognise();
  }

  void _fft(List<int> chunk) {
    for (var i = 0; i < chunk.length; i++) {
      _ring[_ringAt + i] = chunk[i];
    }
    _ringAt = (_ringAt + chunk.length) % _fftSize;
    for (var i = 0; i < _fftSize; i++) {
      _re[i] = _ring[(_ringAt + i) % _fftSize] * _window[i];
      _im[i] = 0;
    }
    fft(_re, _im);
    final out = _spectra[_spectraAt];
    for (var i = 0; i < _bins; i++) {
      final v = (_re[i] * _re[i] + _im[i] * _im[i]) / (1 << 17);
      out[i] = v < 1e-10 ? 1e-10 : v;
    }
    _spectraAt = (_spectraAt + 1) % _history;
  }

  void _spreadPeaks() {
    final spread = Float32List.fromList(_spectra[_back(_spectraAt, -1)]);
    for (var i = 0; i <= _bins - 3; i++) {
      spread[i] = math.max(spread[i], math.max(spread[i + 1], spread[i + 2]));
    }
    for (final before in const [1, 3, 6]) {
      final former = _spread[_back(_spreadAt, -before)];
      for (var i = 0; i < _bins; i++) {
        if (spread[i] > former[i]) former[i] = spread[i];
      }
    }
    _spread[_spreadAt] = spread;
    _spreadAt = (_spreadAt + 1) % _history;
    _spreadWritten++;
  }

  static double _loudness(double v) => math.log(math.max(v, 1 / 64)) * 1477.3 + 6144;

  void _recognise() {
    final minus46 = _spectra[_back(_spectraAt, -46)];
    final minus49 = _spread[_back(_spreadAt, -49)];
    final pass = _spreadWritten - 46;
    for (var bin = 10; bin <= 1014; bin++) {
      final here = minus46[bin];
      if (here < 1 / 64 || here < minus49[bin - 1]) continue;
      var around = 0.0;
      for (final offset in const [-10, -7, -4, -3, 1, 2, 5, 8]) {
        around = math.max(around, minus49[bin + offset]);
      }
      if (here <= around) continue;
      for (final offset in const [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249]) {
        around = math.max(around, _spread[_back(_spreadAt, offset)][bin - 1]);
      }
      if (here <= around) continue;

      final magnitude = _loudness(here);
      final before = _loudness(minus46[bin - 1]);
      final after = _loudness(minus46[bin + 1]);
      final variation1 = magnitude * 2 - before - after;
      if (variation1 <= 0) continue;
      final variation2 = (after - before) * 32 / variation1;
      final corrected = (bin * 64 + variation2.truncate()) & 0xffff;
      final hz = corrected * (sampleRate / 2 / 1024 / 64);
      final int band;
      if (hz >= 250 && hz < 520) {
        band = 0;
      } else if (hz >= 520 && hz < 1450) {
        band = 1;
      } else if (hz >= 1450 && hz < 3500) {
        band = 2;
      } else if (hz >= 3500 && hz <= 5500) {
        band = 3;
      } else {
        continue;
      }
      _bands[band].add(Peak(pass, magnitude.truncate() & 0xffff, corrected));
    }
  }
}

/// An in-place radix-2 FFT.
void fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  final (cosines, sines) = _twiddles(n);
  for (var length = 2; length <= n; length <<= 1) {
    final half = length ~/ 2;
    final step = n ~/ length;
    for (var i = 0; i < n; i += length) {
      for (var k = 0; k < half; k++) {
        final cr = cosines[k * step];
        final ci = sines[k * step];
        final a = i + k;
        final b = a + half;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
      }
    }
  }
}

final _twiddleCache = <int, (Float64List, Float64List)>{};

/// cos and -sin of 2 pi k / n, worked out once for each size rather than by a recurrence that drifts.
(Float64List, Float64List) _twiddles(int n) => _twiddleCache.putIfAbsent(n, () {
  final cosines = Float64List(n ~/ 2);
  final sines = Float64List(n ~/ 2);
  for (var k = 0; k < n ~/ 2; k++) {
    cosines[k] = math.cos(2 * math.pi * k / n);
    sines[k] = -math.sin(2 * math.pi * k / n);
  }
  return (cosines, sines);
});

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

/// CRC-32 (IEEE), as zip and Shazam use it.
int crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return (c ^ 0xffffffff) & 0xffffffff;
}
