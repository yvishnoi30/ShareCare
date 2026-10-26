
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharecare/main.dart';

void main() {
  testWidgets('ShareCare home screen displays correctly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ShareCareApp());
    await tester.pumpAndSettle();

    // Verify the main app renders.
    expect(find.text('ShareCare'), findsWidgets);

    // Verify the app has rendered visible content.
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
