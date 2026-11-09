/// Every screen, drawn into test/goldens/ at a phone's size. `flutter test --update-goldens --tags golden`.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_song_find/app.dart';
import 'package:noctorium_song_find/finder.dart';
import 'package:noctorium_song_find/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  Future<SongFinder> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final f = SongFinder(store: await Store.open(), phone: FakePhone(), client: fakeNetwork(), version: '0.27.0');
    await tester.pumpWidget(SongFindApp(finder: f));
    return f;
  }

  testWidgets('listen', (tester) async {
    await start(tester);
    await expectLater(find.byType(SongFindApp), matchesGoldenFile('goldens/listen.png'));
  });

  testWidgets('found', (tester) async {
    final f = await start(tester);
    await tester.runAsync(() => f.listen());
    await tester.pumpAndSettle();
    await expectLater(find.byType(SongFindApp), matchesGoldenFile('goldens/found.png'));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(SongFindApp), matchesGoldenFile('goldens/history.png'));
  });

  testWidgets('settings', (tester) async {
    await start(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(SongFindApp), matchesGoldenFile('goldens/settings.png'));
  });
}
