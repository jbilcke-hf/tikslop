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
  final _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _promptController.text = _settingsService.videoPromptPrefix;
    _negativePromptController.text = _settingsService.negativeVideoPrompt;
    _hfApiKeyController.text = _settingsService.huggingfaceApiKey;
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    _hfApiKeyController.dispose();
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
          // API Configuration Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API Configuration',
                    style: TextStyle(
                      color: AiTubeColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _hfApiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Connect using your Hugging Face API Key (optional)',
                      helperText: 'Hugging Face members enjoy a higher-resolution rendering.',
                      helperMaxLines: 2,
                    ),
                    obscureText: true,
                    onChanged: (value) async {
                      await _settingsService.setHuggingfaceApiKey(value);
                      
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
                      color: AiTubeColors.onBackground,
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
                      color: AiTubeColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Video Generation Model',
                    ),
                    value: 'ltx-video-0.9.6',
                    onChanged: null, // Disabled
                    items: const [
                      DropdownMenuItem(
                        value: 'ltx-video-0.9.6',
                        child: Text('LTX-Video 0.9.6 (base model)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Interested in using custom Hugging Face models? If you trained a public and distilled LoRA model based on LTX-Video 0.9.6 (remember, it has to be distilled), it can be integrated into AiTube2. Please open a thread in the Community forum and I\'ll see for a way to allow for custom models.',
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

}
