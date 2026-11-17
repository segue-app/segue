import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/theme/theme.dart';

/// WCAG contrast ratio of two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The "Обновить" action of the update snack bar was black on the dark
  // bar: Material's default for it, inversePrimary, fell back to onPrimary.
  testWidgets('snack bar action is readable on the bar', (tester) async {
    final theme = buildTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => ScaffoldMessenger.of(c).showSnackBar(
                SnackBar(
                  content: const Text('Вышла версия'),
                  action: SnackBarAction(label: 'Обновить', onPressed: () {}),
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

    final bar = theme.snackBarTheme.backgroundColor!;
    final label = tester.widget<RichText>(
      find.descendant(
        of: find.byType(SnackBarAction),
        matching: find.byType(RichText),
      ),
    );
    final color = label.text.style!.color!;
    expect(_contrast(color, bar), greaterThan(4.5));

    final content = tester.widget<RichText>(
      find.descendant(
        of: find.text('Вышла версия'),
        matching: find.byType(RichText),
      ),
    );
    expect(_contrast(content.text.style!.color!, bar), greaterThan(4.5));
  });

  test('inverse colors stay readable on each other', () {
    final s = buildTheme().colorScheme;
    expect(_contrast(s.onInverseSurface, s.inverseSurface), greaterThan(4.5));
    expect(_contrast(s.inversePrimary, s.inverseSurface), greaterThan(4.5));
  });
}
