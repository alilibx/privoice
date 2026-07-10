import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted settings (shared_preferences).
class SettingsService {
  static const _kUseLargeModel = 'use_large_model';

  static Future<bool> useLargeModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kUseLargeModel) ?? false;
  }

  static Future<void> setUseLargeModel(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseLargeModel, value);
  }
}
