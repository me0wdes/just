import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/theme/app_theme.dart';
import 'package:day_planner/theme/chroma_swap.dart';

/// Renders the detail swap mid-sweep, to check the band by eye.
void main() {
  testWidgets('chroma swap frames', (tester) async {
    await tester.runAsync(ChromaSwap.load);
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    const c = DayColors.dark;
    final p = [
      for (final k in const [.07, .12, .03]) Color.lerp(c.screen, c.text, k)!,
    ];
    final id = ValueNotifier('A');
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder(
            valueListenable: id,
            builder: (_, value, _) => ChromaSwap(
              swapKey: value,
              colors: p,
              child: ColoredBox(
                color: c.screen,
                child: Center(
                  child: Text(value, style: TextStyle(color: c.text)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // ignore: avoid_print
    print(
      'debug: ${(tester.state(find.byType(ChromaSwap)) as dynamic).shader}',
    );
    id.value = 'B';
    await tester.pump();
    // ignore: avoid_print
    print(
      'anim: ${(tester.state(find.byType(ChromaSwap)) as dynamic).controller.isAnimating}',
    );
    var at = 0;
    for (final ms in [60, 120, 250, 500]) {
      await tester.pump(Duration(milliseconds: ms - at));
      at = ms;
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('../.tools/ui-captures/chroma-$ms.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpAndSettle();
  });
}
