import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/theme/app_theme.dart';
import 'package:day_planner/theme/controls.dart';

void main() {
  testWidgets('select opens, picks, holds the tick, then closes', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    String? value = 'a';
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: dayTheme(Brightness.light),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: StatefulBuilder(
                builder: (context, set) => Align(
                  alignment: Alignment.topLeft,
                  child: DaySelect<String>(
                    value: value,
                    items: const [
                      DaySelectItem('a', 'Входящие'),
                      DaySelectItem('b', 'Дом'),
                      DaySelectItem('c', 'Работа'),
                    ],
                    onChanged: (v) => set(() => value = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Входящие'));
    await tester.pumpAndSettle();
    expect(find.text('Работа'), findsOneWidget);
    if (Platform.environment['CAPTURE'] == '1') {
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../.tools/ui-captures/select-open.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await tester.tap(find.text('Работа'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(value, 'c');
    // Still open during the acknowledgement hold.
    expect(find.text('Дом'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsNothing);
    expect(find.text('Работа'), findsOneWidget);
  });
}
