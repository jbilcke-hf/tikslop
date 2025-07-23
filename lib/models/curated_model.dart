import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// Represents a curated LLM model with metadata
class CuratedModel {
  final String modelId;
  final String displayName;
  final String numOfParameters;

  const CuratedModel({
    required this.modelId,
    required this.displayName,
    required this.numOfParameters,
  });

  /// Get speed category based on parameter count
  String get speedCategory {
    final paramValue = _parseParameters(numOfParameters);
    
    if (paramValue <= 1) return 'Fastest';
    if (paramValue <= 2) return 'Faster';
    if (paramValue <= 4) return 'Fast';
    if (paramValue < 8) return 'Normal';
    if (paramValue < 17) return 'Slow';
    if (paramValue < 32) return 'Slower';
    return 'Slowest';
  }

  /// Get speed emoji for visual representation
  String get speedEmoji {
    switch (speedCategory) {
      case 'Fastest':
        return '🚀';
      case 'Faster':
        return '⚡';
      case 'Fast':
        return '🏃';
      case 'Normal':
        return '🚶';
      case 'Slow':
        return '🐌';
      case 'Slower':
        return '🐢';
      case 'Slowest':
        return '🦥';
      default:
        return '❓';
    }
  }

  /// Parse parameter string to numeric value (in billions)
  double _parseParameters(String params) {
    final numStr = params.replaceAll('B', '').trim();
    return double.tryParse(numStr) ?? 0.0;
  }

  /// Create from YAML map
  factory CuratedModel.fromYaml(YamlMap yaml) {
    return CuratedModel(
      modelId: yaml['model_id'] as String,
      displayName: yaml['display_name'] as String,
      numOfParameters: yaml['num_of_parameters'] as String,
    );
  }

  /// Load all curated models from assets
  static Future<List<CuratedModel>> loadFromAssets() async {
    try {
      final yamlString = await rootBundle.loadString('assets/config/curated_models.yaml');
      final yamlData = loadYaml(yamlString);
      
      final models = <CuratedModel>[];
      if (yamlData['models'] != null) {
        for (final modelYaml in yamlData['models']) {
          models.add(CuratedModel.fromYaml(modelYaml));
        }
      }
      
      // Sort by parameter count (smallest first)
      models.sort((a, b) => a._parseParameters(a.numOfParameters)
          .compareTo(b._parseParameters(b.numOfParameters)));
      
      return models;
    } catch (e) {
      // Return default models if loading fails
      return _defaultModels;
    }
  }

  /// Default models in case asset loading fails
  static const List<CuratedModel> _defaultModels = [
    CuratedModel(
      modelId: 'meta-llama/Llama-3.2-3B-Instruct',
      displayName: 'Llama 3.2 3B Instruct',
      numOfParameters: '3B',
    ),
    CuratedModel(
      modelId: 'HuggingFaceTB/SmolLM3-3B',
      displayName: 'SmolLM3 3B',
      numOfParameters: '3B',
    ),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CuratedModel &&
          runtimeType == other.runtimeType &&
          modelId == other.modelId;

  @override
  int get hashCode => modelId.hashCode;

  @override
  String toString() => 'CuratedModel(modelId: $modelId, displayName: $displayName, parameters: $numOfParameters)';
}