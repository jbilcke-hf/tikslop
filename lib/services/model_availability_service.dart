import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents the availability status of a model for a specific provider
class ModelProviderAvailability {
  final String providerId;
  final String status; // 'live' or 'staging'
  final String task; // e.g., 'conversational'
  final String? mappedLLMProviderId; // Our internal provider ID

  const ModelProviderAvailability({
    required this.providerId,
    required this.status,
    required this.task,
    this.mappedLLMProviderId,
  });

  bool get isLive => status == 'live';

  factory ModelProviderAvailability.fromJson(
    String hfProviderId,
    Map<String, dynamic> json,
  ) {
    return ModelProviderAvailability(
      providerId: json['providerId'] ?? hfProviderId,
      status: json['status'] ?? 'unknown',
      task: json['task'] ?? 'unknown',
    );
  }
}

/// Cached model availability information
class ModelAvailabilityCache {
  final String modelId;
  final List<ModelProviderAvailability> providers;
  final DateTime lastUpdated;

  const ModelAvailabilityCache({
    required this.modelId,
    required this.providers,
    required this.lastUpdated,
  });

  bool get isExpired {
    final now = DateTime.now();
    final difference = now.difference(lastUpdated);
    return difference.inSeconds > 30; // 30 seconds cache duration
  }

  List<ModelProviderAvailability> get liveProviders =>
      providers.where((p) => p.isLive).toList();
}

/// Service for querying and caching model availability from Hugging Face API
class ModelAvailabilityService {
  static const String _baseUrl = 'https://huggingface.co/api/models';

  // Cache for model availability data
  final Map<String, ModelAvailabilityCache> _cache = {};

  /// Mapping from HF provider IDs to our internal LLM provider IDs
  static const Map<String, String> _providerMapping = {
    'cerebras': 'cerebras',
    'cohere': 'cohere',
    'fal-ai': 'fal-ai',
    'featherless': 'featherless',
    'fireworks': 'fireworks',
    'groq': 'groq',
    'hf-inference': 'hf-inference',
    'hyperbolic': 'hyperbolic',
    'nebius': 'nebius',
    'novita': 'novita',
    'nscale': 'nscale',
    'replicate': 'replicate',
    'sambanova': 'sambanova',
    'together': 'together',
  };

  /// Get model availability, using cache if available and not expired
  Future<ModelAvailabilityCache?> getModelAvailability(String modelId) async {
    // Check cache first
    final cached = _cache[modelId];
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    // Fetch fresh data from API
    try {
      final availability = await _fetchModelAvailability(modelId);
      if (availability != null) {
        _cache[modelId] = availability;
      }
      return availability;
    } catch (e) {
      // If API call fails and we have cached data, return it even if expired
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  /// Fetch model availability from Hugging Face API
  Future<ModelAvailabilityCache?> _fetchModelAvailability(
    String modelId,
  ) async {
    final url = '$_baseUrl/$modelId?expand[]=inferenceProviderMapping';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json', 'User-Agent': '#tikslop-App/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseModelAvailability(modelId, data);
      } else if (response.statusCode == 404) {
        // Model not found, return empty availability
        return ModelAvailabilityCache(
          modelId: modelId,
          providers: [],
          lastUpdated: DateTime.now(),
        );
      } else {
        throw ModelAvailabilityException(
          'Failed to fetch model availability: HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is ModelAvailabilityException) {
        rethrow;
      }
      throw ModelAvailabilityException('Network error: $e');
    }
  }

  /// Parse the API response into ModelAvailabilityCache
  ModelAvailabilityCache _parseModelAvailability(
    String modelId,
    Map<String, dynamic> data,
  ) {
    final providers = <ModelProviderAvailability>[];

    final inferenceMapping =
        data['inferenceProviderMapping'] as Map<String, dynamic>?;
    if (inferenceMapping != null) {
      for (final entry in inferenceMapping.entries) {
        final hfProviderId = entry.key;
        final providerData = entry.value as Map<String, dynamic>;

        final availability = ModelProviderAvailability.fromJson(
          hfProviderId,
          providerData,
        );

        // Map HF provider ID to our internal provider ID
        final mappedProviderId = _providerMapping[hfProviderId];
        if (mappedProviderId != null) {
          providers.add(
            ModelProviderAvailability(
              providerId: availability.providerId,
              status: availability.status,
              task: availability.task,
              mappedLLMProviderId: mappedProviderId,
            ),
          );
        } else {
          // Keep unmapped providers for potential future use
          providers.add(availability);
        }
      }
    }

    return ModelAvailabilityCache(
      modelId: modelId,
      providers: providers,
      lastUpdated: DateTime.now(),
    );
  }

  /// Get list of compatible LLM providers for a model
  List<String> getCompatibleProviders(String modelId) {
    final cached = _cache[modelId];
    if (cached == null) {
      return [];
    }

    return cached.liveProviders
        .where((p) => p.mappedLLMProviderId != null)
        .map((p) => p.mappedLLMProviderId!)
        .toList();
  }

  /// Check if a specific provider supports a model
  bool isProviderCompatible(String modelId, String llmProviderId) {
    final compatibleProviders = getCompatibleProviders(modelId);
    return compatibleProviders.contains(llmProviderId);
  }

  /// Get the provider-specific model name for a given model and provider
  String? getProviderSpecificModelName(String modelId, String llmProviderId) {
    final cached = _cache[modelId];
    if (cached == null) {
      return null;
    }

    final providerAvailability = cached.liveProviders
        .where((p) => p.mappedLLMProviderId == llmProviderId)
        .firstOrNull;

    return providerAvailability?.providerId;
  }

  /// Clear cache for a specific model
  void clearCache(String modelId) {
    _cache.remove(modelId);
  }

  /// Clear all cached data
  void clearAllCache() {
    _cache.clear();
  }

  /// Get cache status for debugging
  Map<String, bool> getCacheStatus() {
    return _cache.map((key, value) => MapEntry(key, !value.isExpired));
  }
}

/// Exception thrown when model availability operations fail
class ModelAvailabilityException implements Exception {
  final String message;

  ModelAvailabilityException(this.message);

  @override
  String toString() => 'ModelAvailabilityException: $message';
}