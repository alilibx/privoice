import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboardingComplete defaults to false, persists true', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SettingsService.onboardingComplete(), isFalse);

    await SettingsService.setOnboardingComplete(true);
    expect(await SettingsService.onboardingComplete(), isTrue);
  });
}
