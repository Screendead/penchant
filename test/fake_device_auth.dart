import 'package:tracker/app_lock/device_auth.dart';

class FakeDeviceAuth implements DeviceAuth {
  FakeDeviceAuth({
    this.available = true,
    this.biometry = Biometry.faceID,
    List<AuthOutcome>? outcomes,
  }) : outcomes = outcomes ?? <AuthOutcome>[];

  bool available;
  final Biometry biometry;
  final List<AuthOutcome> outcomes;
  int asked = 0;

  @override
  Future<DeviceAuthStatus> status() async =>
      DeviceAuthStatus(available: available, biometry: biometry);

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    asked++;
    return outcomes.isEmpty ? AuthOutcome.success : outcomes.removeAt(0);
  }
}
