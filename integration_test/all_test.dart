// Every integration file in one app build: flutter test rebuilds and reinstalls
// the app for each file it is given. Each file still runs alone.

import 'package:flutter_test/flutter_test.dart';

import 'about_version_test.dart' as about_version_test;
import 'accessibility_test.dart' as accessibility_test;
import 'account_switch_test.dart' as account_switch_test;
import 'account_test.dart' as account_test;
import 'activity_flows_test.dart' as activity_flows_test;
import 'archive_test.dart' as archive_test;
import 'bounded_queries_test.dart' as bounded_queries_test;
import 'cold_start_test.dart' as cold_start_test;
import 'error_states_test.dart' as error_states_test;
import 'navigation_test.dart' as navigation_test;
import 'offline_test.dart' as offline_test;
import 'onboarding_test.dart' as onboarding_test;
import 'rejected_write_test.dart' as rejected_write_test;
import 'smoke_test.dart' as smoke_test;
import 'split_view_test.dart' as split_view_test;
import 'trends_test.dart' as trends_test;
import 'write_flows_test.dart' as write_flows_test;

void main() {
  group('about_version_test', about_version_test.main);
  group('accessibility_test', accessibility_test.main);
  group('account_switch_test', account_switch_test.main);
  group('account_test', account_test.main);
  group('activity_flows_test', activity_flows_test.main);
  group('archive_test', archive_test.main);
  group('bounded_queries_test', bounded_queries_test.main);
  group('cold_start_test', cold_start_test.main);
  group('error_states_test', error_states_test.main);
  group('navigation_test', navigation_test.main);
  group('offline_test', offline_test.main);
  group('onboarding_test', onboarding_test.main);
  group('rejected_write_test', rejected_write_test.main);
  group('smoke_test', smoke_test.main);
  group('split_view_test', split_view_test.main);
  group('trends_test', trends_test.main);
  group('write_flows_test', write_flows_test.main);
}
