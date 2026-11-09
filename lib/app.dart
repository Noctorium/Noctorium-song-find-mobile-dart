/// The app: Listen, History and Settings, behind a bar at the foot of the screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'finder.dart';
import 'providers.dart';
import 'song.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/mark.dart';

const releasesPage = 'https://github.com/Noctorium/Noctorium-Installer/releases/latest';

class SongFindApp extends StatelessWidget {
  const SongFindApp({super.key, required this.finder});

  final SongFinder finder;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Noctorium Song Find',
    debugShowCheckedModeBanner: false,
    theme: nightTheme(),
    home: Home(finder: finder),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.finder});

  final SongFinder finder;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  var _page = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.finder,
    builder: (context, _) {
      final finder = widget.finder;
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: const Row(
            children: [
              Mark(size: 30),
              SizedBox(width: 12),
              Text('Song Find', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        body: Column(
          children: [
            if (finder.newer != null) UpdateBanner(finder: finder),
            Expanded(
              child: switch (_page) {
                0 => ListenPage(finder: finder),
                1 => HistoryPage(finder: finder, onListen: () => setState(() => _page = 0)),
                _ => SettingsPage(finder: finder),
              },
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: Night.panel,
          indicatorColor: Night.accent.withValues(alpha: .25),
          selectedIndex: _page,
          onDestinationSelected: (i) => setState(() => _page = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Listen'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
          ],
        ),
      );
    },
  );
}

Future<void> open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

// ------------------------------------------------------------------------------------------------ update

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.finder});

  final SongFinder finder;

  @override
  Widget build(BuildContext context) {
    final release = finder.newer!;
    final line = switch (finder.updating) {
      Updating.nothing => 'Song Find ${release.version} is out.',
      Updating.downloading => 'Downloading ${release.version}… ${(finder.downloaded * 100).round()}%',
      Updating.handed => 'Android is installing ${release.version}.',
      Updating.failed => finder.updateProblem ?? 'The update could not be installed.',
    };
    return Material(
      color: Night.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(line, style: const TextStyle(color: Night.text)),
            ),
            TextButton(onPressed: () => open(release.page.toString()), child: const Text("What's new")),
            if (release.apk != null && finder.updating != Updating.downloading)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: finder.installUpdate,
                child: const Text('Install'),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------------ Listen

class ListenPage extends StatelessWidget {
  const ListenPage({super.key, required this.finder});

  final SongFinder finder;

  String get _status => switch (finder.activity) {
    Activity.idle when finder.shown != null && finder.problem == null => 'Found it',
    Activity.idle => 'Tap to find the song',
    Activity.listening =>
      'Listening to the ${finder.settings.source == Source.system ? 'phone' : 'room'}… ${(finder.settings.seconds * (1 - finder.fraction)).ceil()}s',
    Activity.asking => 'Asking ${finder.asking?.label ?? 'the providers'}…',
  };

  @override
  Widget build(BuildContext context) {
    final settings = finder.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Center(
          child: SegmentedButton<Source>(
            segments: const [
              ButtonSegment(value: Source.microphone, label: Text('Microphone'), icon: Icon(Icons.mic)),
              ButtonSegment(value: Source.system, label: Text('Phone audio'), icon: Icon(Icons.phone_android)),
            ],
            selected: {settings.source},
            onSelectionChanged: finder.busy ? null : (s) => finder.change(settings.copyWith(source: s.first)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          settings.source == Source.system
              ? (finder.systemAudioSupported
                    ? 'Listens to what this phone is playing: a video, a stream, another app. Android asks first.'
                    : 'Listening to what the phone plays needs Android 10 or later.')
              : 'Listens through the microphone, to a song playing nearby.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Night.faint),
        ),
        const SizedBox(height: 24),
        Center(
          child: BigButton(finder: finder, compact: !finder.busy && finder.shown != null),
        ),
        const SizedBox(height: 18),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Night.text, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        if (finder.problem != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(finder.problem!, style: const TextStyle(color: Color(0xFFFFC46B))),
            ),
          ),
        if (!finder.busy && finder.shown != null) SongCard(song: finder.shown!),
        if (finder.answers.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What each provider said',
                    style: TextStyle(color: Night.text, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  for (final (provider, answer) in finder.answers)
                    InkWell(
                      onTap: answer is Found ? () => finder.show(answer.song) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: switch (answer) {
                                Found() => Night.accent,
                                Unknown() => Night.faint,
                                Failed() => Night.error,
                              },
                            ),
                            const SizedBox(width: 8),
                            Text(
                              provider.label,
                              style: const TextStyle(color: Night.text, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(switch (answer) {
                                Found(:final song) => '${song.artist} — ${song.title}',
                                Unknown() => 'did not know it',
                                Failed(:final why) => why,
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.finder, this.compact = false});

  final SongFinder finder;

  /// Smaller once a song is shown, so the song is on screen without scrolling.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final busy = finder.busy;
    return Semantics(
      button: true,
      label: busy ? 'Stop listening' : 'Listen',
      child: GestureDetector(
        onTap: finder.listen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: compact ? 120 : 220,
          height: compact ? 120 : 220,
          child: CustomPaint(
            painter: _Rings(
              busy: busy,
              level: finder.level,
              fraction: finder.activity == Activity.listening ? finder.fraction : null,
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: compact ? 92 : 132,
                height: compact ? 92 : 132,
                decoration: BoxDecoration(
                  color: Night.accent,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Night.accent.withValues(alpha: busy ? .55 : .3), blurRadius: 60)],
                ),
                child: Icon(busy ? Icons.stop_rounded : Icons.graphic_eq, size: compact ? 44 : 64, color: onAccent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rings extends CustomPainter {
  _Rings({required this.busy, required this.level, required this.fraction});

  final bool busy;
  final double level;
  final double? fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    if (!busy) return;
    final grow = math.sqrt(level.clamp(0, 1));
    for (var i = 0; i < 3; i++) {
      final r = 72 + (i + 1) * (10 + 12 * grow);
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Night.accent.withValues(alpha: .6 - i * .18),
      );
    }
    if (fraction case final f?) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: 76),
        -math.pi / 2,
        2 * math.pi * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(Night.accent, Night.text, .4)!,
      );
    }
  }

  @override
  bool shouldRepaint(_Rings old) => old.busy != busy || old.level != level || old.fraction != fraction;
}

class SongCard extends StatelessWidget {
  const SongCard({super.key, required this.song, this.trailing});

  final Song song;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final facts = [song.album, song.year, song.genre, song.label].whereType<String>().join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Cover(url: song.cover, size: 104),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: const TextStyle(color: Night.text, fontSize: 21, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        style: TextStyle(
                          color: Color.lerp(Night.accent, Night.text, .3),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (facts.isNotEmpty) ...[const SizedBox(height: 6), Text(facts)],
                      if (song.provider.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Found by ${song.provider}', style: TextStyle(color: Night.faint, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (name, url) in song.links)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => open(url),
                    child: Text(name),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${song.artist} – ${song.title}'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                ),
              ],
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class Cover extends StatelessWidget {
  const Cover({super.key, required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final blank = Container(
      width: size,
      height: size,
      color: Night.page,
      child: Icon(Icons.music_note, color: Night.faint, size: size * .45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .12),
      child: url == null
          ? blank
          : Image.network(url!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => blank),
    );
  }
}

// ----------------------------------------------------------------------------------------------- History

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.finder, required this.onListen});

  final SongFinder finder;
  final VoidCallback onListen;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  var _filter = '';
  Entry? _open;

  Future<void> _clear() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the history?'),
        content: const Text('Every song found is forgotten. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (sure == true) await widget.finder.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final finder = widget.finder;
    final needle = _filter.toLowerCase();
    final shown = [
      for (final e in finder.history)
        if (needle.isEmpty || '${e.song.title} ${e.song.artist} ${e.song.album ?? ''}'.toLowerCase().contains(needle))
          e,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'History',
                style: TextStyle(color: Night.text, fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            if (finder.history.isNotEmpty) TextButton(onPressed: _clear, child: const Text('Clear')),
          ],
        ),
        Text(
          'Every song found, on this phone only. Nothing here is sent anywhere.',
          style: TextStyle(color: Night.faint),
        ),
        const SizedBox(height: 12),
        if (finder.history.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Nothing found yet. The songs you find show up here.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: widget.onListen, child: const Text('Find a song')),
                ],
              ),
            ),
          )
        else ...[
          TextField(
            decoration: const InputDecoration(hintText: 'Search the history', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: 12),
          for (final entry in shown)
            if (identical(entry, _open))
              SongCard(
                song: entry.song,
                trailing: Row(
                  children: [
                    TextButton(onPressed: () => setState(() => _open = null), child: const Text('Close')),
                    TextButton(
                      onPressed: () {
                        setState(() => _open = null);
                        finder.remove(entry);
                      },
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              )
            else
              Card(
                child: ListTile(
                  onTap: () => setState(() => _open = entry),
                  leading: Cover(url: entry.song.cover, size: 48),
                  title: Text(
                    entry.song.title,
                    style: const TextStyle(color: Night.text, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('${entry.song.artist}\n${_when(entry.at)} · ${entry.source} · ${entry.song.provider}'),
                  isThreeLine: true,
                ),
              ),
        ],
      ],
    );
  }

  static String _when(DateTime at) {
    final l = at.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.day} ${months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
  }
}

// ---------------------------------------------------------------------------------------------- Settings

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.finder});

  final SongFinder finder;

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Night.text, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = finder.settings;
    final keys = s.keys;
    Keys keysWith({String? audd, String? host, String? key, String? secret}) => Keys(
      auddToken: audd ?? keys.auddToken,
      acrHost: host ?? keys.acrHost,
      acrKey: key ?? keys.acrKey,
      acrSecret: secret ?? keys.acrSecret,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const Text(
          'Settings',
          style: TextStyle(color: Night.text, fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _section('Listening', [
          const Text('Listen for'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [for (final n in Settings.lengths) ButtonSegment(value: n, label: Text('$n s'))],
            selected: {Settings.lengths.contains(s.seconds) ? s.seconds : 10},
            onSelectionChanged: (v) => finder.change(s.copyWith(seconds: v.first)),
          ),
          const SizedBox(height: 6),
          Text(
            'Longer is surer in a noisy room; ten seconds is plenty for most songs.',
            style: TextStyle(color: Night.faint, fontSize: 12),
          ),
        ]),
        _section('Providers', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ask every provider'),
            subtitle: const Text('Not only until one knows the song'),
            value: s.askEveryone,
            onChanged: (v) => finder.change(s.copyWith(askEveryone: v)),
          ),
          for (var i = 0; i < s.providers.length; i++)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Night.page, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Switch(
                        value: s.providers[i].$2,
                        onChanged: (v) =>
                            finder.change(s.copyWith(providers: [...s.providers]..[i] = (s.providers[i].$1, v))),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.providers[i].$1.label,
                          style: const TextStyle(color: Night.text, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ask sooner',
                        onPressed: i == 0
                            ? null
                            : () => finder.change(
                                s.copyWith(
                                  providers: [...s.providers]
                                    ..[i] = s.providers[i - 1]
                                    ..[i - 1] = s.providers[i],
                                ),
                              ),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Ask later',
                        onPressed: i == s.providers.length - 1
                            ? null
                            : () => finder.change(
                                s.copyWith(
                                  providers: [...s.providers]
                                    ..[i] = s.providers[i + 1]
                                    ..[i + 1] = s.providers[i],
                                ),
                              ),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                    ],
                  ),
                  Text(s.providers[i].$1.about, style: TextStyle(color: Night.faint, fontSize: 12)),
                  if (keys.missing(s.providers[i].$1) case final why?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(why, style: const TextStyle(color: Color(0xFFFFC46B), fontSize: 12)),
                    ),
                  ...switch (s.providers[i].$1) {
                    Provider.shazam => const <Widget>[],
                    Provider.audd => [
                      _Field(
                        'API token (optional)',
                        keys.auddToken,
                        secret: true,
                        onChanged: (v) => finder.change(s.copyWith(keys: keysWith(audd: v))),
                      ),
                      TextButton(
                        onPressed: () => open('https://dashboard.audd.io/'),
                        child: const Text('Get a token at audd.io'),
                      ),
                    ],
                    Provider.acrcloud => [
                      _Field(
                        'Host',
                        keys.acrHost,
                        hint: 'identify-eu-west-1.acrcloud.com',
                        onChanged: (v) => finder.change(s.copyWith(keys: keysWith(host: v))),
                      ),
                      _Field(
                        'Access key',
                        keys.acrKey,
                        onChanged: (v) => finder.change(s.copyWith(keys: keysWith(key: v))),
                      ),
                      _Field(
                        'Access secret',
                        keys.acrSecret,
                        secret: true,
                        onChanged: (v) => finder.change(s.copyWith(keys: keysWith(secret: v))),
                      ),
                      TextButton(
                        onPressed: () => open('https://console.acrcloud.com/'),
                        child: const Text('Make a project at console.acrcloud.com'),
                      ),
                    ],
                  },
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Keys stay on this phone and are sent only to their own provider. AcoustID is on the desktop app.',
            style: TextStyle(color: Night.faint, fontSize: 12),
          ),
        ]),
        _section('History', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep a history of the songs found'),
            subtitle: Text('${finder.history.length} songs, kept on this phone only'),
            value: s.keepHistory,
            onChanged: (v) => finder.change(s.copyWith(keepHistory: v)),
          ),
        ]),
        _section('Updates', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check for a newer release at start'),
            subtitle: Text('This is version ${finder.version}'),
            value: s.checkForUpdates,
            onChanged: (v) => finder.change(s.copyWith(checkForUpdates: v)),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final found = await finder.checkForUpdate();
                  if (!found) messenger.showSnackBar(const SnackBar(content: Text('This is the newest.')));
                },
                child: const Text('Check now'),
              ),
              TextButton(onPressed: () => open(releasesPage), child: const Text('Releases')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Also on Obtainium: add github.com/Noctorium/Noctorium-Installer and filter for Noctorium-Song-Find.',
            style: TextStyle(color: Night.faint, fontSize: 12),
          ),
        ]),
        _section('About', [
          Text('Noctorium Song Find ${finder.version}', style: const TextStyle(color: Night.text)),
          const SizedBox(height: 4),
          const Text(
            "Part of Noctorium. Free software under the GNU GPL, version 3. Shazam's fingerprint is made as SongRec worked it out.",
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => open('https://github.com/Noctorium/Noctorium-song-find-mobile-dart'),
                child: const Text('Source'),
              ),
              TextButton(onPressed: () => open('https://noctorium.vercel.app'), child: const Text('Website')),
            ],
          ),
        ]),
      ],
    );
  }
}

class _Field extends StatefulWidget {
  const _Field(this.label, this.value, {required this.onChanged, this.secret = false, this.hint});

  final String label;
  final String value;
  final bool secret;
  final String? hint;
  final ValueChanged<String> onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      controller: _controller,
      obscureText: widget.secret,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
      onChanged: widget.onChanged,
    ),
  );
}
