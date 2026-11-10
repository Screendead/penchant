// Every integration file in one app build: flutter test rebuilds and reinstalls
// the app for each file it is given. Each file still runs alone.

import 'package:flutter_test/flutter_test.dart';

import 'account_test.dart' as account_test;
import 'activity_flows_test.dart' as activity_flows_test;
import 'bounded_queries_test.dart' as bounded_queries_test;
import 'category_migration_test.dart' as category_migration_test;
import 'cold_start_test.dart' as cold_start_test;
import 'error_states_test.dart' as error_states_test;
import 'guest_test.dart' as guest_test;
import 'offline_test.dart' as offline_test;
import 'rejected_write_test.dart' as rejected_write_test;
import 'sealed_fields_test.dart' as sealed_fields_test;
import 'sealing_migration_test.dart' as sealing_migration_test;
import 'smoke_test.dart' as smoke_test;
import 'trends_test.dart' as trends_test;
import 'write_flows_test.dart' as write_flows_test;

void main() {
  group('account_test', account_test.main);
  group('activity_flows_test', activity_flows_test.main);
  group('bounded_queries_test', bounded_queries_test.main);
  group('category_migration_test', category_migration_test.main);
  group('cold_start_test', cold_start_test.main);
  group('error_states_test', error_states_test.main);
  group('guest_test', guest_test.main);
  group('offline_test', offline_test.main);
  group('rejected_write_test', rejected_write_test.main);
  group('sealed_fields_test', sealed_fields_test.main);
  group('sealing_migration_test', sealing_migration_test.main);
  group('smoke_test', smoke_test.main);
  group('trends_test', trends_test.main);
  group('write_flows_test', write_flows_test.main);
}
