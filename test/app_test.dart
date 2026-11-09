import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_song_find/app.dart';
import 'package:noctorium_song_find/finder.dart';
import 'package:noctorium_song_find/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

Future<SongFinder> songFinder({FakePhone? phone, Object? shazam}) async {
  SharedPreferences.setMockInitialValues({});
  return SongFinder(
    store: await Store.open(),
    phone: phone ?? FakePhone(),
    client: shazam == null ? fakeNetwork() : fakeNetwork(shazam: shazam),
    version: '0.27.0',
  );
}

void main() {
  testWidgets('listening finds the song, shows it, and keeps it in the history', (tester) async {
    final f = await songFinder();
    await tester.pumpWidget(SongFindApp(finder: f));
    expect(find.text('Tap to find the song'), findsOneWidget);

    await tester.runAsync(() => f.listen());
    await tester.pumpAndSettle();
    expect(find.text('Found it'), findsOneWidget);
    expect(find.text('Never Gonna Give You Up'), findsWidgets);
    expect(find.text('Rick Astley'), findsOneWidget);
    expect(f.history.single.song.provider, 'Shazam');

    // Kept on the phone, across a restart.
    expect((await Store.open()).history.single.song.title, 'Never Gonna Give You Up');

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Never Gonna Give You Up'), findsOneWidget);
  });

  testWidgets('a song nobody knows says so, and nothing is kept', (tester) async {
    final f = await songFinder(shazam: const {'matches': []});
    await tester.pumpWidget(SongFindApp(finder: f));
    await tester.runAsync(() => f.listen());
    await tester.pumpAndSettle();
    expect(find.textContaining('No song was found'), findsOneWidget);
    expect(f.history, isEmpty);
  });

  testWidgets('a microphone that may not be used says why', (tester) async {
    final f = await songFinder(phone: FakePhone(error: 'Song Find may not use the microphone.'));
    await tester.pumpWidget(SongFindApp(finder: f));
    await tester.runAsync(() => f.listen());
    await tester.pumpAndSettle();
    expect(find.text('Song Find may not use the microphone.'), findsOneWidget);
  });

  testWidgets('settings are kept, and the history can be turned off', (tester) async {
    final f = await songFinder();
    await tester.pumpWidget(SongFindApp(finder: f));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 s'));
    await tester.pumpAndSettle();
    expect((await Store.open()).settings.seconds, 15);

    f.change(f.settings.copyWith(keepHistory: false));
    await tester.runAsync(() => f.listen());
    expect(f.history, isEmpty);
  });

  testWidgets('switching to phone audio is remembered', (tester) async {
    final f = await songFinder();
    await tester.pumpWidget(SongFindApp(finder: f));
    await tester.tap(find.text('Phone audio'));
    await tester.pumpAndSettle();
    expect(f.settings.source, Source.system);
    expect(find.textContaining('what this phone is playing'), findsOneWidget);
  });

  testWidgets('every page draws at twice the text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await songFinder();
    await tester.pumpWidget(SongFindApp(finder: f));
    for (final page in ['History', 'Settings', 'Listen']) {
      await tester.tap(find.text(page).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
