import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/features/settings/connection_panel.dart';

void main() {
  test('reads the string printed by server/install.sh', () {
    // Produced by the same printf | base64 | tr pipeline as install.sh.
    final parsed = parseConnectionString(
      ' just1:eyJ1IjoiaHR0cHM6Ly8xLTItMy00LnNzbGlwLmlvL3N5bmMiLCJrIjoiQWJDX2RlZi0xMjMifQ ',
    );
    expect(parsed?.endpoint.toString(), 'https://1-2-3-4.sslip.io/sync');
    expect(parsed?.key, 'AbC_def-123');
  });

  test('rejects anything that is not a just1 https link', () {
    expect(parseConnectionString('https://example.com/sync'), isNull);
    expect(parseConnectionString('just1:not-base64!'), isNull);
    const http = 'just1:eyJ1IjoiaHR0cDovL3guaW8vc3luYyIsImsiOiJrIn0';
    expect(parseConnectionString(http), isNull);
  });
}
