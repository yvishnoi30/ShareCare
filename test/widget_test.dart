import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharecare/main.dart';

void main() {
  testWidgets('ShareCare home screen displays correctly', (
    WidgetTester tester,
  ) async {
    // Use a desktop-sized test surface.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ShareCareApp());
    await tester.pumpAndSettle();

    expect(find.text('ShareCare'), findsOneWidget);
    expect(find.text('Share files. Simply.'), findsOneWidget);
    expect(find.text('Select files to send'), findsOneWidget);
    expect(find.text('No files selected'), findsOneWidget);
  });
}
