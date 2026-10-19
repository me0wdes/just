import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/theme/fluid_switch.dart';

void main() {
  testWidgets(
    'switch toggles once by label, keyboard and drag, and cancels safely',
    (tester) async {
      var value = false, calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => FluidSwitchTile(
                title: const Text('Звук'),
                value: value,
                onChanged: (v) => setState(() {
                  value = v;
                  calls++;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Звук'));
      await tester.pumpAndSettle();
      expect(value, true);
      expect(calls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, false);
      expect(calls, 2);
      await tester.drag(
        find.byKey(const Key('fluid-switch-track')),
        const Offset(38, 0),
      );
      await tester.pumpAndSettle();
      expect(value, true);
      expect(calls, 3);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('fluid-switch-track'))),
      );
      await gesture.moveBy(const Offset(-16, 0));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(value, true);
      expect(calls, 3);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switch reverses from its current position and reduced motion settles immediately',
    (tester) async {
      var value = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: false),
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return FluidSwitchTile(
                  title: const Text('Звук'),
                  value: value,
                  onChanged: (v) => setState(() => value = v),
                );
              },
            ),
          ),
        ),
      );
      final thumb = find.byKey(const Key('fluid-switch-thumb'));
      final start = tester.getCenter(thumb).dx;
      await tester.tap(find.text('Звук'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final mid = tester.getCenter(thumb).dx;
      expect(mid, greaterThan(start));
      update(() => value = false);
      await tester.pump();
      expect((tester.getCenter(thumb).dx - mid).abs(), lessThan(1));
      await tester.pumpAndSettle();
      expect(tester.getCenter(thumb).dx, closeTo(start, .1));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: FluidSwitchTile(
              title: const Text('Статично'),
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
