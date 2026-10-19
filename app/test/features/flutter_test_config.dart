import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  // Static widget tests must settle despite the ambient header.
  // Motion tests explicitly override MediaQuery to exercise moving states.
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  await main();
}
