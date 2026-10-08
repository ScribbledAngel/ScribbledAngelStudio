import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scribbled_angel_studio/app.dart';

void main() {
  testWidgets('App launches to the Home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ScribbledAngelStudioApp());
    await tester.pumpAndSettle();

    expect(find.text('Scribbled Angel Studio'), findsOneWidget);
    expect(find.text('Your Projects'), findsOneWidget);
  });
}
