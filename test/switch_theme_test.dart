import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/ui/theme/theme.dart';

void main() {
  test('an "on" switch keeps its dark knob under the cursor', () {
    final thumb = buildTheme().switchTheme.thumbColor!;
    for (final state in [
      <WidgetState>{WidgetState.selected},
      {WidgetState.selected, WidgetState.hovered},
      {WidgetState.selected, WidgetState.pressed},
      {WidgetState.selected, WidgetState.focused},
    ]) {
      expect(thumb.resolve(state), SegueColors.ink, reason: '$state');
    }
    // "Off" keeps Material's own look.
    expect(thumb.resolve({WidgetState.hovered}), isNull);
  });
}
