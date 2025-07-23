/// LLM Provider configuration for Hugging Face supported providers
class LLMProvider {
  final String id;
  final String name;
  final String? apiBaseUrl;
  final String routerBaseUrl;
  final bool supportsHuggingFaceKey;
  final bool isAvailable;

  const LLMProvider({
    required this.id,
    required this.name,
    this.apiBaseUrl,
    required this.routerBaseUrl,
    this.supportsHuggingFaceKey = true,
    this.isAvailable = true,
  });

  /// Create a copy with updated availability
  LLMProvider copyWith({bool? isAvailable}) {
    return LLMProvider(
      id: id,
      name: name,
      apiBaseUrl: apiBaseUrl,
      routerBaseUrl: routerBaseUrl,
      supportsHuggingFaceKey: supportsHuggingFaceKey,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  /// Get the API key label for this provider
  String get apiKeyLabel {
    if (!supportsHuggingFaceKey) {
      return '$name API Key';
    }
    return 'Hugging Face API Key';
  }

  /// List of all supported providers based on HF documentation
  static const List<LLMProvider> supportedProviders = [
    LLMProvider(
      id: 'built-in',
      name: 'Built-in (free, slow)',
      routerBaseUrl: '',
      supportsHuggingFaceKey: false,
    ),
    LLMProvider(
      id: 'cerebras',
      name: 'Cerebras',
      apiBaseUrl: 'https://api.cerebras.ai/v1',
      routerBaseUrl: 'https://router.huggingface.co/cerebras/v1',
    ),
    LLMProvider(
      id: 'cohere',
      name: 'Cohere',
      apiBaseUrl: 'https://api.cohere.com/compatibility/v1',
      routerBaseUrl: 'https://router.huggingface.co/cohere/v1',
    ),
    LLMProvider(
      id: 'fal-ai',
      name: 'Fal AI',
      apiBaseUrl: 'https://api.fal.ai/v1',
      routerBaseUrl: 'https://router.huggingface.co/fal-ai/v1',
    ),
    LLMProvider(
      id: 'featherless',
      name: 'Featherless AI',
      apiBaseUrl: 'https://api.featherless.ai/v1',
      routerBaseUrl: 'https://router.huggingface.co/featherless/v1',
    ),
    LLMProvider(
      id: 'fireworks',
      name: 'Fireworks',
      apiBaseUrl: 'https://api.fireworks.ai/inference/v1',
      routerBaseUrl: 'https://router.huggingface.co/fireworks/v1',
    ),
    LLMProvider(
      id: 'groq',
      name: 'Groq',
      apiBaseUrl: 'https://api.groq.com/openai/v1',
      routerBaseUrl: 'https://router.huggingface.co/groq/v1',
    ),
    LLMProvider(
      id: 'hf-inference',
      name: 'HF Inference',
      apiBaseUrl: 'https://api-inference.huggingface.co/v1',
      routerBaseUrl: 'https://router.huggingface.co/hf-inference/v1',
    ),
    LLMProvider(
      id: 'hyperbolic',
      name: 'Hyperbolic',
      apiBaseUrl: 'https://api.hyperbolic.xyz/v1',
      routerBaseUrl: 'https://router.huggingface.co/hyperbolic/v1',
    ),
    LLMProvider(
      id: 'nebius',
      name: 'Nebius',
      apiBaseUrl: 'https://api.studio.nebius.ai/v1',
      routerBaseUrl: 'https://router.huggingface.co/nebius/v1',
    ),
    LLMProvider(
      id: 'novita',
      name: 'Novita',
      apiBaseUrl: 'https://api.novita.ai/v3/openai',
      routerBaseUrl: 'https://router.huggingface.co/novita/v1',
    ),
    LLMProvider(
      id: 'nscale',
      name: 'Nscale',
      apiBaseUrl: 'https://inference.api.nscale.com/v1',
      routerBaseUrl: 'https://router.huggingface.co/nscale/v1',
    ),
    LLMProvider(
      id: 'replicate',
      name: 'Replicate',
      apiBaseUrl: 'https://api.replicate.com/v1',
      routerBaseUrl: 'https://router.huggingface.co/replicate/v1',
    ),
    LLMProvider(
      id: 'sambanova',
      name: 'SambaNova',
      apiBaseUrl: 'https://api.sambanova.ai/v1',
      routerBaseUrl: 'https://router.huggingface.co/sambanova/v1',
    ),
    LLMProvider(
      id: 'together',
      name: 'Together',
      apiBaseUrl: 'https://api.together.xyz/v1',
      routerBaseUrl: 'https://router.huggingface.co/together/v1',
    ),
  ];

  /// Get provider by ID
  static LLMProvider? getById(String id) {
    try {
      return supportedProviders.firstWhere((provider) => provider.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get default provider
  static LLMProvider get defaultProvider {
    return supportedProviders.first; // Built-in is first in the list
  }
}