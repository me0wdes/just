import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/platform/update_service.dart';

void main() {
  test('versions compare by number, not by text', () {
    expect(isNewer('0.2.10', '0.2.9'), isTrue);
    expect(isNewer('0.3.0', '0.2.9'), isTrue);
    expect(isNewer('0.2.4', '0.2.4'), isFalse);
    expect(isNewer('0.2.3', '0.2.4'), isFalse);
    expect(isNewer('1.0', '0.9.9'), isTrue);
  });
}
