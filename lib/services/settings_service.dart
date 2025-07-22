import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tikslop/config/config.dart';

class SettingsService {
  static const String _promptPrefixKey = 'video_prompt_prefix';
  static const String _hfApiKeyKey = 'huggingface_api_key';
  static const String _negativePromptKey = 'negative_video_prompt';
  static const String _showSceneDebugInfoKey = 'show_scene_debug_info';
  static const String _enableSimulationKey = 'enable_simulation';
  static const String _llmProviderKey = 'llm_provider';
  static const String _llmModelKey = 'llm_model';
  static const String _llmApiKeyKey = 'llm_api_key';
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

  String get negativeVideoPrompt => _prefs.getString(_negativePromptKey) ?? Configuration.instance.defaultNegativePrompt;

  Future<void> setNegativeVideoPrompt(String negativePrompt) async {
    await _prefs.setString(_negativePromptKey, negativePrompt);
    _settingsController.add(null);
  }

  String get huggingfaceApiKey => _prefs.getString(_hfApiKeyKey) ?? '';

  Future<void> setHuggingfaceApiKey(String apiKey) async {
    await _prefs.setString(_hfApiKeyKey, apiKey);
    _settingsController.add(null);
  }
  
  bool get showSceneDebugInfo => _prefs.getBool(_showSceneDebugInfoKey) ?? false;
  
  Future<void> setShowSceneDebugInfo(bool value) async {
    await _prefs.setBool(_showSceneDebugInfoKey, value);
    _settingsController.add(null);
  }
  
  bool get enableSimulation => _prefs.getBool(_enableSimulationKey) ?? Configuration.instance.enableSimLoop;
  
  Future<void> setEnableSimulation(bool value) async {
    await _prefs.setBool(_enableSimulationKey, value);
    _settingsController.add(null);
  }

  String get llmProvider => _prefs.getString(_llmProviderKey) ?? 'openai';
  
  Future<void> setLlmProvider(String provider) async {
    await _prefs.setString(_llmProviderKey, provider);
    _settingsController.add(null);
  }

  String get llmModel => _prefs.getString(_llmModelKey) ?? 'gpt-4';
  
  Future<void> setLlmModel(String model) async {
    await _prefs.setString(_llmModelKey, model);
    _settingsController.add(null);
  }

  String get llmApiKey => _prefs.getString(_llmApiKeyKey) ?? '';
  
  Future<void> setLlmApiKey(String apiKey) async {
    await _prefs.setString(_llmApiKeyKey, apiKey);
    _settingsController.add(null);
  }

  void dispose() {
    _settingsController.close();
  }
}
