import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/screens/shell.dart';

void main() {
  testWidgets('a focused search field takes the keys, not the shortcuts', (
    tester,
  ) async {
    final field = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(focusNode: field)),
      ),
    );
    expect(isTyping(), isFalse);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(field.hasFocus, isTrue);
    expect(isTyping(), isTrue); // Space types a space, not pause
    field.unfocus();
    await tester.pump();
    expect(isTyping(), isFalse);
  });
}
