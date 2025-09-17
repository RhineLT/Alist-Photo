// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alist_photo/main.dart';

void main() {
  testWidgets('App loads without error', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Wait for initialization to complete
    await tester.pumpAndSettle();

    // Should show either the main content or initialization screen
    // Look for either loading indicator or app content
    expect(
      find.byType(CircularProgressIndicator).or(find.text('Alist Photo')),
      findsOneWidget,
    );
  });

  testWidgets('App initialization completes', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    
    // Wait for initialization to complete with longer timeout
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // After initialization, should show the main app
    expect(find.byType(Scaffold), findsAtLeastOneWidget);
  });
}
