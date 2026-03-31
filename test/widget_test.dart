import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance/main.dart';

void main() {
  testWidgets('Resonance app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ResonanceApp());

    expect(find.text('Resonance'), findsOneWidget);
  });
}
