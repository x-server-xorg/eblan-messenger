import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/translations.dart';

class LanguageProvider extends ChangeNotifier {
  String _locale = 'en';

  String get locale => _locale;
  Translations get t => Translations(_locale);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = prefs.getString('locale') ?? 'en';
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
    notifyListeners();
  }
}
