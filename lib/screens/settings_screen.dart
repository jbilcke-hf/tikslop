import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/websocket_api_service.dart';
import '../services/model_availability_service.dart';
import '../models/llm_provider.dart';
import '../models/curated_model.dart';
import '../theme/colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _promptController = TextEditingController();
  final _negativePromptController = TextEditingController();
  final _hfApiKeyController = TextEditingController();
  final _llmApiKeyController = TextEditingController();
  final _modelNameController = TextEditingController();
  final _settingsService = SettingsService();
  final _availabilityService = ModelAvailabilityService();
  bool _showSceneDebugInfo = false;
  bool _enableSimulation = true;
  String _selectedLlmProvider = 'built-in';
  String _selectedLlmModel = 'meta-llama/Llama-3.2-3B-Instruct';
  LLMProvider? _currentProvider;
  List<LLMProvider> _availableProviders = LLMProvider.supportedProviders.where((p) => p.id != 'built-in').toList();
  List<CuratedModel> _curatedModels = [];
  CuratedModel? _selectedCuratedModel;
  bool _isCheckingAvailability = false;
  bool _isLoadingModels = true;
  bool _isBuiltInModelSelected = true;

  @override
  void initState() {
    super.initState();
    _promptController.text = _settingsService.videoPromptPrefix;
    _negativePromptController.text = _settingsService.negativeVideoPrompt;
    _hfApiKeyController.text = _settingsService.huggingfaceApiKey;
    _llmApiKeyController.text = _settingsService.llmApiKey;
    _showSceneDebugInfo = _settingsService.showSceneDebugInfo;
    _enableSimulation = _settingsService.enableSimulation;
    
    // Auto-select built-in model if no HF API key
    if (_settingsService.huggingfaceApiKey.isEmpty) {
      _selectedLlmProvider = 'built-in';
      _selectedLlmModel = 'built-in';
      _isBuiltInModelSelected = true;
      // Save the auto-selected values
      _settingsService.setLlmProvider('built-in');
      _settingsService.setLlmModel('built-in');
    } else {
      _selectedLlmProvider = _settingsService.llmProvider;
      _selectedLlmModel = _settingsService.llmModel;
      _isBuiltInModelSelected = _selectedLlmModel == 'built-in';
    }
    _currentProvider = _isBuiltInModelSelected ? null : LLMProvider.getById(_selectedLlmProvider);
    _modelNameController.text = _selectedLlmModel;
    
    // Load curated models
    _loadCuratedModels();
    
    // Check model availability on startup
    if (!_isBuiltInModelSelected) {
      _checkModelAvailability();
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    _hfApiKeyController.dispose();
    _llmApiKeyController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }
  
  Future<void> _loadCuratedModels() async {
    try {
      final models = await CuratedModel.loadFromAssets();
      setState(() {
        _curatedModels = models;
        _isLoadingModels = false;
        
        // Find the currently selected model in the curated list
        if (!_isBuiltInModelSelected) {
          try {
            _selectedCuratedModel = _curatedModels.firstWhere(
              (model) => model.modelId == _selectedLlmModel,
            );
          } catch (e) {
            // If current model not found in curated list, use first available
            _selectedCuratedModel = _curatedModels.isNotEmpty ? _curatedModels.first : null;
          }
        } else {
          _selectedCuratedModel = null;
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingModels = false;
      });
    }
  }
  
  Future<void> _checkModelAvailability() async {
    if (!mounted || _selectedLlmModel.isEmpty) return;

    setState(() {
      _isCheckingAvailability = true;
    });

    try {
      final availability = await _availabilityService.getModelAvailability(
        _selectedLlmModel,
      );
      if (availability != null && mounted) {
        final compatibleProviders = _availabilityService.getCompatibleProviders(
          _selectedLlmModel,
        );

        // Update provider availability
        final updatedProviders = LLMProvider.supportedProviders.map((provider) {
          if (provider.id == 'built-in') {
            return provider; // Built-in is always available
          }
          final isCompatible = compatibleProviders.contains(provider.id);
          return provider.copyWith(isAvailable: isCompatible);
        }).toList();

        setState(() {
          _availableProviders = updatedProviders;
          _isCheckingAvailability = false;
        });

        // Auto-switch provider if current one is not compatible
        if (!compatibleProviders.contains(_selectedLlmProvider) && !_isBuiltInModelSelected) {
          if (compatibleProviders.isNotEmpty) {
            // Switch to first compatible provider
            setState(() {
              _selectedLlmProvider = compatibleProviders.first;
              _currentProvider = LLMProvider.getById(_selectedLlmProvider);
            });
            await _settingsService.setLlmProvider(_selectedLlmProvider);
          } else {
            // No compatible providers, switch to built-in model
            setState(() {
              _selectedLlmProvider = 'built-in';
              _selectedLlmModel = 'built-in';
              _isBuiltInModelSelected = true;
              _selectedCuratedModel = null;
              _currentProvider = null;
            });
            await _settingsService.setLlmProvider('built-in');
            await _settingsService.setLlmModel('built-in');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingAvailability = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to check model availability: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // LLM Configuration Card (moved to top)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Story Engine',
                    style: TextStyle(
                      color: TikSlopColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '#tikslop uses a language model (LLM) to generate search results and video descriptions.',
                    style: TextStyle(
                      color: TikSlopColors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'A basic LLM is available by default for free, but it has limited capacity. Switch to another LLM for best performance.',
                    style: TextStyle(
                      color: TikSlopColors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _hfApiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Hugging Face API Key',
                      helperText: 'Providing a HF API key allows you to select faster or better LLMs (billed to your account)',
                      helperMaxLines: 2,
                    ),
                    obscureText: true,
                    onChanged: (value) async {
                      await _settingsService.setHuggingfaceApiKey(value);
                      
                      // Auto-select built-in provider if API key is removed
                      if (value.isEmpty && !_isBuiltInModelSelected) {
                        setState(() {
                          _selectedLlmProvider = 'built-in';
                          _selectedLlmModel = 'built-in';
                          _isBuiltInModelSelected = true;
                          _currentProvider = null;
                          _selectedCuratedModel = null;
                          _modelNameController.text = _selectedLlmModel;
                        });
                        await _settingsService.setLlmProvider('built-in');
                        await _settingsService.setLlmModel('built-in');
                      } else if (value.isNotEmpty) {
                        // Trigger rebuild to enable/disable fields
                        setState(() {});
                        // Check model availability when HF key is provided
                        if (!_isBuiltInModelSelected) {
                          _checkModelAvailability();
                        }
                      }
                      
                      // Show a snackbar to indicate the API key was saved
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('API Key saved. Reconnecting...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      
                      // Reinitialize the websocket connection when the API key changes
                      final websocket = WebSocketApiService();
                      try {
                        // Force reconnection with the new API key
                        await websocket.reconnect();
                        
                        // Show success message
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Connected successfully with new API key'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        // Show error message if connection fails
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to connect: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Model selection dropdown
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Model',
                      helperText: _isBuiltInModelSelected
                          ? 'The built-in model is free, but shared among users and may be out of capacity sometimes'
                          : _hfApiKeyController.text.isEmpty 
                              ? 'Enter HF API key to select models' 
                              : _isCheckingAvailability
                                  ? 'Checking model availability...'
                                  : 'Tikslop works best with a fast model (recommended: Gemma 2 9B)',
                      suffixIcon: _isCheckingAvailability || _isLoadingModels
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    value: _isBuiltInModelSelected ? 'built-in' : _selectedCuratedModel?.modelId,
                    onChanged: (String? newValue) async {
                      if (newValue == 'built-in') {
                        setState(() {
                          _isBuiltInModelSelected = true;
                          _selectedLlmModel = 'built-in';
                          _selectedLlmProvider = 'built-in';
                          _selectedCuratedModel = null;
                          _currentProvider = null;
                        });
                        await _settingsService.setLlmModel('built-in');
                        await _settingsService.setLlmProvider('built-in');
                      } else if (newValue != null) {
                        final newModel = _curatedModels.firstWhere(
                          (model) => model.modelId == newValue,
                        );
                        setState(() {
                          _isBuiltInModelSelected = false;
                          _selectedCuratedModel = newModel;
                          _selectedLlmModel = newModel.modelId;
                          // Reset to first available provider if we had built-in selected
                          if (_selectedLlmProvider == 'built-in') {
                            _selectedLlmProvider = _availableProviders.isNotEmpty ? _availableProviders.first.id : 'hf-inference';
                            _currentProvider = LLMProvider.getById(_selectedLlmProvider);
                          }
                        });
                        await _settingsService.setLlmModel(newModel.modelId);
                        if (_selectedLlmProvider != 'built-in') {
                          await _settingsService.setLlmProvider(_selectedLlmProvider);
                        }
                        // Check availability after model change
                        _checkModelAvailability();
                      }
                    },
                    selectedItemBuilder: (BuildContext context) {
                      final allItems = <String>['built-in', ..._curatedModels.map((m) => m.modelId)];
                      return allItems.map((itemValue) {
                        if (itemValue == 'built-in') {
                          return const Row(
                            children: [
                              Text('🏠'),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Built-in (default, free)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        } else {
                          final model = _curatedModels.firstWhere((m) => m.modelId == itemValue);
                          return Row(
                            children: [
                              Text(model.speedEmoji),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  model.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        }
                      }).toList();
                    },
                    items: _hfApiKeyController.text.isNotEmpty
                        ? [
                            // Scenario 1: HF API key provided - show all models including built-in
                            const DropdownMenuItem<String>(
                              value: 'built-in',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text('🏠'),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Built-in (default, free)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(left: 24),
                                    child: Text(
                                      'Slow and unreliable',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ..._curatedModels.map((model) {
                              return DropdownMenuItem<String>(
                                value: model.modelId,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Text(model.speedEmoji),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            model.displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 24),
                                      child: Text(
                                        '${model.numOfParameters} • ${model.speedCategory}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ]
                        : [
                            // Scenario 2: No HF API key - only show built-in and disabled message
                            const DropdownMenuItem<String>(
                              value: 'built-in',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text('🏠'),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Built-in (default, free)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(left: 24),
                                    child: Text(
                                      'Slow and unreliable',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const DropdownMenuItem<String>(
                              value: null,
                              enabled: false,
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  'To use other models you need a HF API key',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                          ],
                  ),
                  if (!_isBuiltInModelSelected) ...[                  
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'LLM Provider',
                        helperText: _hfApiKeyController.text.isEmpty 
                            ? 'Enter HF API key to unlock providers' 
                            : _isCheckingAvailability
                                ? 'Checking model availability...'
                                : 'Tikslop works best with a fast provider (eg. Groq)',
                        helperMaxLines: 2,
                      ),
                      value: _selectedLlmProvider == 'built-in' ? null : _selectedLlmProvider,
                      onChanged: _hfApiKeyController.text.isEmpty ? null : (String? newValue) {
                        if (newValue != null) {
                          // Check if provider is available for this model
                          final provider = _availableProviders.firstWhere(
                            (p) => p.id == newValue,
                            orElse: () => _availableProviders.first,
                          );
                          
                          if (!provider.isAvailable) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${provider.name} does not support this model'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          
                          setState(() {
                            _selectedLlmProvider = newValue;
                            _currentProvider = provider;
                          });
                          _settingsService.setLlmProvider(newValue);
                        }
                      },
                      items: _availableProviders.map((provider) {
                        final isAvailable = provider.isAvailable;
                        return DropdownMenuItem(
                          value: provider.id,
                          enabled: isAvailable,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  provider.name,
                                  style: TextStyle(
                                    color: isAvailable ? null : Colors.grey,
                                  ),
                                ),
                              ),
                              if (!isAvailable)
                                const Icon(
                                  Icons.lock,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  /*
                  The Hugging Face Inference Providers allow the user to either use their HF API key,
                  which will bill them automatically on the HF account, or pass a provider-specific
                  API key, which will bill them on their provider account.

                  This is a nice feature, but for now let's just use the transparent/automatic billing.

                  So I've disabled this whole section:
                  
                  if (!_isBuiltInModelSelected) ...[                  
                    const SizedBox(height: 16),
                    TextField(
                      controller: _llmApiKeyController,
                      decoration: InputDecoration(
                        labelText: _currentProvider?.apiKeyLabel ?? 'API Key',
                        helperText: _hfApiKeyController.text.isEmpty 
                            ? 'Enter HF API key above to enable provider options' 
                            : _currentProvider?.supportsHuggingFaceKey == true
                                ? 'Your HF API key will be automatically used for this provider'
                                : 'Optional - provider-specific API key',
                        helperMaxLines: 2,
                      ),
                      obscureText: true,
                      enabled: _hfApiKeyController.text.isNotEmpty && 
                               _currentProvider?.supportsHuggingFaceKey == false,
                      onChanged: (value) async {
                        await _settingsService.setLlmApiKey(value);
                      },
                    ),
                  ],
                  */
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Video Prompt Prefix Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rendering Engine',
                    style: TextStyle(
                      color: TikSlopColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Note: while #tikslop uses GPUs courtesy of Hugging Face, is not an official project but simply a demo made by @jbilcke-hf and should be considered like beta software.',
                    style: TextStyle(
                      color: TikSlopColors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Because of this free hosting (and the experimental nature of the app), the stream might get slowed down or interrupted at anytime in case of traffic surge or unplanned maintenance.',
                    style: TextStyle(
                      color: TikSlopColors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _promptController,
                    decoration: const InputDecoration(
                      labelText: 'Video Prompt Prefix',
                      helperText: 'Text to prepend to all video generation prompts',
                      helperMaxLines: 2,
                    ),
                    onChanged: (value) {
                      _settingsService.setVideoPromptPrefix(value);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _negativePromptController,
                    decoration: const InputDecoration(
                      labelText: 'Negative Prompt',
                      helperText: 'Content to avoid in the output generation',
                      helperMaxLines: 2,
                    ),
                    onChanged: (value) {
                      _settingsService.setNegativeVideoPrompt(value);
                    },
                  ),

                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Real-time Video Model (free and built-in, cannot be changed yet)',
                    ),
                    initialValue: 'ltx-video-2b-0.9.8',
                    onChanged: null, // Disabled
                    items: const [
                      DropdownMenuItem(
                        value: 'ltx-video-2b-0.9.8',
                        child: Text('LTX-Video 2B 0.9.8 (distilled)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please ping @flngr on X if you have made your own LoRA for this model, or if you know a faster open-source model with similar memory footprint.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Display Options Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Developer Tools (beta)',
                    style: TextStyle(
                      color: TikSlopColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Show scene debug information'),
                    subtitle: const Text('Display initial, current, and last description in video view'),
                    value: _showSceneDebugInfo,
                    onChanged: (value) {
                      setState(() {
                        _showSceneDebugInfo = value;
                      });
                      _settingsService.setShowSceneDebugInfo(value);
                    },
                  ),
                  /*
                  let's disable this for now, I still need to work on this
                  SwitchListTile(
                    title: const Text('Enable world simulator engine'),
                    subtitle: const Text('Allow video descriptions to evolve over time using a LLM (this consumes tokens, your Hugging Face account will be billed)'),
                    value: _enableSimulation,
                    onChanged: (value) {
                      setState(() {
                        _enableSimulation = value;
                      });
                      _settingsService.setEnableSimulation(value);
                    },
                  ),
                  */
                  const SizedBox(height: 16),
                  // Clear device connections button
                  ListTile(
                    title: const Text('Clear Device Connections'),
                    subtitle: const Text('Clear all cached device connections (useful if you see "Too many connections" error)'),
                    trailing: ElevatedButton(
                      onPressed: () {
                        // Clear all device connections
                        WebSocketApiService.clearAllDeviceConnections();
                        
                        // Show confirmation message
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Device connections cleared. Please reload the page.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      child: const Text('Clear All'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


}
