import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyrenamer/main.dart';

void main() {
  testWidgets('App starts with title', (WidgetTester tester) async {
    // Build our app and trigger a frame
    await tester.pumpWidget(const MyApp());

    // Verify the app title exists
    expect(find.text('Image Renamer'), findsOneWidget);
  });

  testWidgets('Folder selection button exists', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    // Find the choose folder button
    expect(find.text('Choose Folder'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('Manual path input works', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    // Tap the choose folder button
    await tester.tap(find.text('Choose Folder'));
    await tester.pumpAndSettle();
    
    // Should show manual path dialog
    expect(find.text('Paste a folder path'), findsOneWidget);
    
    // Enter a path
    await tester.enterText(find.byType(TextField), '/test/path');
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    
    // Verify path was set (you'd need to expose some state for this)
    expect(find.text('/test/path'), findsOneWidget);
  });

  testWidgets('Shows empty state initially', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    // Should show empty state message
    expect(find.text('No folder selected'), findsOneWidget);
    expect(find.text('No images found'), findsOneWidget);
  });

  testWidgets('Pattern input exists', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    // Should have pattern input field
    expect(find.byKey(const Key('patternField')), findsOneWidget);
    expect(find.text('Pattern'), findsOneWidget);
  });
}