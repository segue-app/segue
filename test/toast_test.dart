import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // With a button, Flutter keeps a note on screen until it's closed by
  // hand unless told otherwise; Segue's notes (errors too) go by themselves.
  testWidgets('a note with a button goes away by itself', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => ScaffoldMessenger.of(c).showSnackBar(
                SnackBar(
                  content: const Text('Не удалось воспроизвести'),
                  duration: const Duration(seconds: 3),
                  persist: false,
                  action: SnackBarAction(
                    label: 'Проверить связь',
                    onPressed: () {},
                  ),
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось воспроизвести'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось воспроизвести'), findsNothing);
  });
}
