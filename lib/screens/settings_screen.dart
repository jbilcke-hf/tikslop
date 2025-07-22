import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/websocket_api_service.dart';
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
  final _settingsService = SettingsService();
  bool _showSceneDebugInfo = false;
  bool _enableSimulation = true;
  String _selectedLlmProvider = 'openai';
  String _selectedLlmModel = 'gpt-4';

  @override
  void initState() {
    super.initState();
    _promptController.text = _settingsService.videoPromptPrefix;
    _negativePromptController.text = _settingsService.negativeVideoPrompt;
    _hfApiKeyController.text = _settingsService.huggingfaceApiKey;
    _llmApiKeyController.text = _settingsService.llmApiKey;
    _showSceneDebugInfo = _settingsService.showSceneDebugInfo;
    _enableSimulation = _settingsService.enableSimulation;
    
    // Auto-select built-in provider if no HF API key
    if (_settingsService.huggingfaceApiKey.isEmpty) {
      _selectedLlmProvider = 'builtin';
      _selectedLlmModel = 'default';
      // Save the auto-selected values
      _settingsService.setLlmProvider('builtin');
      _settingsService.setLlmModel('default');
    } else {
      _selectedLlmProvider = _settingsService.llmProvider;
      _selectedLlmModel = _settingsService.llmModel;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    _hfApiKeyController.dispose();
    _llmApiKeyController.dispose();
    super.dispose();
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
                    'LLM Configuration',
                    style: TextStyle(
                      color: TikSlopColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _hfApiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Hugging Face API Key',
                      helperText: 'Your HF token for API access and higher-resolution rendering',
                      helperMaxLines: 2,
                    ),
                    obscureText: true,
                    onChanged: (value) async {
                      await _settingsService.setHuggingfaceApiKey(value);
                      
                      // Auto-select built-in provider if API key is removed
                      if (value.isEmpty && _selectedLlmProvider != 'builtin') {
                        setState(() {
                          _selectedLlmProvider = 'builtin';
                          _selectedLlmModel = 'default';
                        });
                        await _settingsService.setLlmProvider('builtin');
                        await _settingsService.setLlmModel('default');
                      } else if (value.isNotEmpty) {
                        // Trigger rebuild to enable/disable fields
                        setState(() {});
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
                        // First dispose the current connection
                        await websocket.dispose();
                        
                        // Then create a new connection with the new API key
                        await websocket.connect();
                        
                        // Finally, initialize the connection completely
                        await websocket.initialize();
                        
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
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'LLM Provider',
                      helperText: _hfApiKeyController.text.isEmpty 
                          ? 'Enter HF API key to unlock providers' 
                          : 'Select your preferred LLM provider',
                    ),
                    value: _selectedLlmProvider,
                    onChanged: _hfApiKeyController.text.isEmpty ? null : (String? newValue) {
                      if (newValue != null) {
                        // Prevent selecting non-builtin providers without HF API key
                        if (_hfApiKeyController.text.isEmpty && newValue != 'builtin') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please provide a Hugging Face API key to use external providers'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        setState(() {
                          _selectedLlmProvider = newValue;
                          // Reset model when provider changes
                          if (newValue == 'builtin') {
                            _selectedLlmModel = 'default';
                          } else {
                            _selectedLlmModel = _getModelsForProvider(newValue).first.value!;
                          }
                        });
                        _settingsService.setLlmProvider(newValue);
                        _settingsService.setLlmModel(_selectedLlmModel);
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'builtin',
                        child: Text('Built-in (free, slow)'),
                      ),
                      DropdownMenuItem(
                        value: 'openai',
                        child: Text('OpenAI'),
                      ),
                      DropdownMenuItem(
                        value: 'anthropic',
                        child: Text('Anthropic'),
                      ),
                      DropdownMenuItem(
                        value: 'google',
                        child: Text('Google'),
                      ),
                      DropdownMenuItem(
                        value: 'cohere',
                        child: Text('Cohere'),
                      ),
                      DropdownMenuItem(
                        value: 'together',
                        child: Text('Together AI'),
                      ),
                      DropdownMenuItem(
                        value: 'huggingface',
                        child: Text('Hugging Face'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'LLM Model',
                      helperText: _hfApiKeyController.text.isEmpty 
                          ? 'Using default built-in model' 
                          : 'Select the model to use',
                    ),
                    value: _selectedLlmModel,
                    onChanged: _hfApiKeyController.text.isEmpty ? null : (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedLlmModel = newValue;
                        });
                        _settingsService.setLlmModel(newValue);
                      }
                    },
                    items: _getModelsForProvider(_selectedLlmProvider),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _llmApiKeyController,
                    decoration: InputDecoration(
                      labelText: _getLlmApiKeyLabel(),
                      helperText: _hfApiKeyController.text.isEmpty 
                          ? 'Enter HF API key above to enable provider options' 
                          : 'Optional - will use your HF API key if not provided',
                      helperMaxLines: 2,
                    ),
                    obscureText: true,
                    enabled: _hfApiKeyController.text.isNotEmpty,
                    onChanged: (value) async {
                      await _settingsService.setLlmApiKey(value);
                    },
                  ),
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
                    'Video Generation',
                    style: TextStyle(
                      color: TikSlopColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                    'Display Options',
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
                  SwitchListTile(
                    title: const Text('Enable simulation'),
                    subtitle: const Text('Allow video descriptions to evolve over time'),
                    value: _enableSimulation,
                    onChanged: (value) {
                      setState(() {
                        _enableSimulation = value;
                      });
                      _settingsService.setEnableSimulation(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Custom Video Model Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Custom Video Model',
                    style: TextStyle(
                      color: TikSlopColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Video Generation Model',
                    ),
                    value: 'ltx-video-2b-0.9.8',
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
                    'Interested in using custom Hugging Face models? If you already have trained a LoRA model based on LTX-Video 2B 0.9.8 (distilled), please open a thread in the Community forum and I\'ll see for a way to allow for custom models.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
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

  List<DropdownMenuItem<String>> _getModelsForProvider(String provider) {
    switch (provider) {
      case 'builtin':
        return const [
          DropdownMenuItem(value: 'default', child: Text('Default Model')),
        ];
      case 'openai':
        return const [
          DropdownMenuItem(value: 'gpt-4', child: Text('GPT-4')),
          DropdownMenuItem(value: 'gpt-4-turbo', child: Text('GPT-4 Turbo')),
          DropdownMenuItem(value: 'gpt-3.5-turbo', child: Text('GPT-3.5 Turbo')),
        ];
      case 'anthropic':
        return const [
          DropdownMenuItem(value: 'claude-3-opus', child: Text('Claude 3 Opus')),
          DropdownMenuItem(value: 'claude-3-sonnet', child: Text('Claude 3 Sonnet')),
          DropdownMenuItem(value: 'claude-3-haiku', child: Text('Claude 3 Haiku')),
        ];
      case 'google':
        return const [
          DropdownMenuItem(value: 'gemini-1.5-pro', child: Text('Gemini 1.5 Pro')),
          DropdownMenuItem(value: 'gemini-1.5-flash', child: Text('Gemini 1.5 Flash')),
          DropdownMenuItem(value: 'gemini-pro', child: Text('Gemini Pro')),
        ];
      case 'cohere':
        return const [
          DropdownMenuItem(value: 'command-r-plus', child: Text('Command R Plus')),
          DropdownMenuItem(value: 'command-r', child: Text('Command R')),
          DropdownMenuItem(value: 'command', child: Text('Command')),
        ];
      case 'together':
        return const [
          DropdownMenuItem(value: 'meta-llama/Llama-3.2-3B-Instruct', child: Text('Llama 3.2 3B')),
          DropdownMenuItem(value: 'mistralai/Mixtral-8x7B-Instruct-v0.1', child: Text('Mixtral 8x7B')),
          DropdownMenuItem(value: 'deepseek-ai/deepseek-coder', child: Text('DeepSeek Coder')),
        ];
      case 'huggingface':
        return const [
          DropdownMenuItem(value: 'HuggingFaceTB/SmolLM3-3B', child: Text('SmolLM3 3B')),
          DropdownMenuItem(value: 'meta-llama/Llama-3.2-3B-Instruct', child: Text('Llama 3.2 3B')),
          DropdownMenuItem(value: 'microsoft/Phi-3-mini-4k-instruct', child: Text('Phi-3 Mini')),
        ];
      default:
        return const [
          DropdownMenuItem(value: 'default', child: Text('Default Model')),
        ];
    }
  }

  String _getLlmApiKeyLabel() {
    switch (_selectedLlmProvider) {
      case 'builtin':
        return 'API Key (Not required for built-in)';
      case 'openai':
        return 'OpenAI API Key';
      case 'anthropic':
        return 'Anthropic API Key';
      case 'google':
        return 'Google AI API Key';
      case 'cohere':
        return 'Cohere API Key';
      case 'together':
        return 'Together AI API Key';
      case 'huggingface':
        return 'Hugging Face API Key';
      default:
        return 'API Key';
    }
  }

}
