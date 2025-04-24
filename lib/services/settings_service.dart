import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _promptPrefixKey = 'video_prompt_prefix';
  static const String _hfApiKeyKey = 'huggingface_api_key';
  static final SettingsService _instance = SettingsService._internal();
  
  factory SettingsService() => _instance;
  SettingsService._internal();

  late SharedPreferences _prefs;
  final _settingsController = StreamController<void>.broadcast();

  Stream<void> get settingsStream => _settingsController.stream;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get videoPromptPrefix => _prefs.getString(_promptPrefixKey) ?? '';

  Future<void> setVideoPromptPrefix(String prefix) async {
    await _prefs.setString(_promptPrefixKey, prefix);
    _settingsController.add(null);
  }

  String get huggingfaceApiKey => _prefs.getString(_hfApiKeyKey) ?? '';

  Future<void> setHuggingfaceApiKey(String apiKey) async {
    await _prefs.setString(_hfApiKeyKey, apiKey);
    _settingsController.add(null);
  }

  void dispose() {
    _settingsController.close();
  }
}
