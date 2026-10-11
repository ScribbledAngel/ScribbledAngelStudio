import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:scribbled_angel_studio/app.dart';
import 'package:scribbled_angel_studio/data/app_storage.dart';

/// Widget tests run with no real platform behind plugin channels, so
/// anything that calls path_provider (storage load/save, reference assets)
/// needs a fake backing it - otherwise the call just hangs/throws and the
/// app gets stuck on its loading screen forever.
class _FakePathProviderPlatform extends PathProviderPlatform {
  final String _tempPath = Directory.systemTemp.createTempSync('scribbled_angel_studio_test_').path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tempPath;
}

void main() {
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  testWidgets('App launches to the Home screen', (WidgetTester tester) async {
    // AppState.load() does real (if fake-backed) file I/O, and widget tests
    // run in a fake-time zone that doesn't let real async I/O complete on
    // its own - runAsync briefly steps outside that zone for it.
    await tester.runAsync(() => AppStorage.init());
    await tester.pumpWidget(const ScribbledAngelStudioApp());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    // The loading screen shown in the meantime is an indeterminate spinner
    // that animates forever by design, so pump a bounded number of times
    // rather than pumpAndSettle (which would never return while it's up).
    for (var i = 0; i < 10 && find.text('Scribbled Angel Studio').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Scribbled Angel Studio'), findsOneWidget);
    expect(find.text('Your Projects'), findsOneWidget);
  });
}
