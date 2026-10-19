// Runs the same real Node + two-file SQLite scenario under the native runner.
import 'package:integration_test/integration_test.dart';

import '../test/sync/two_clients_test.dart' as scenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  scenarios.main();
}
