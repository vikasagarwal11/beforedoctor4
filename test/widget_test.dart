// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pv_reporting/data/repositories/mock_repo.dart';
import 'package:pv_reporting/main.dart';

void main() {
  testWidgets('App boots and shows navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MyApp(repo: MockRepo.bootstrap()),
      ),
    );

    // Let initial build complete (avoid pumpAndSettle due to repeating animations).
    await tester.pump(const Duration(milliseconds: 50));

    // Bottom navigation labels from AppShell.
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });
}
