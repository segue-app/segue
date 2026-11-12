import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/widgets/wavy_progress.dart';

void main() {
  Future<List<double>> pump(WidgetTester tester) async {
    final seeks = <double>[];
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              // The mini player around it opens the full player on tap.
              onTap: () => opened++,
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 60, child: Text('track')),
                    SeekLine(progress: 0.1, color: Colors.red, onSeek: seeks.add),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    addTearDown(() => expect(opened, 0, reason: 'seeking must not open'));
    return seeks;
  }

  testWidgets('tap on the line seeks there', (tester) async {
    final seeks = await pump(tester);
    final line = tester.getRect(find.byType(SeekLine));
    await tester.tapAt(Offset(line.left + line.width * 0.25, line.center.dy));
    await tester.pump(const Duration(seconds: 5));
    expect(seeks.single, closeTo(0.25, 0.02));
  });

  testWidgets('drag along the line seeks where it ends', (tester) async {
    final seeks = await pump(tester);
    final line = tester.getRect(find.byType(SeekLine));
    await tester.dragFrom(
      Offset(line.left + 40, line.center.dy),
      Offset(line.width * 0.6, 0),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(seeks.single, closeTo((40 + line.width * 0.6) / line.width, 0.03));
  });
}
