import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted settings (shared_preferences).
class SettingsService {
  static const _kUseLargeModel = 'use_large_model';
  static const _kThemeMode = 'theme_mode';

  static Future<bool> useLargeModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kUseLargeModel) ?? false;
  }

  static Future<void> setUseLargeModel(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseLargeModel, value);
  }

  static Future<ThemeMode> themeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_kThemeMode));
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  static ThemeMode _parse(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
