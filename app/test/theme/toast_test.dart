import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/theme/toast.dart';

void main() {
  for (final (size, top) in [
    (const Size(375, 812), true),
    (const Size(1280, 800), false),
  ]) {
    testWidgets(
      'toast sits ${top ? 'on top on a phone' : 'above the bottom on a computer'}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var undone = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => DayToast.show(
                    context,
                    'Задача удалена',
                    action: 'Отменить',
                    onAction: () => undone = true,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        final box = tester.getRect(find.text('Задача удалена'));
        if (top) {
          expect(box.top, lessThan(80));
        } else {
          expect(size.height - box.bottom, greaterThan(96));
        }
        await tester.tap(find.text('Отменить'));
        await tester.pumpAndSettle();
        expect(undone, isTrue);
        expect(find.text('Задача удалена'), findsNothing);
      },
    );
  }
}
