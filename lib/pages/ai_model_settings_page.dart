import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/api_key_dialog.dart';
import '../config/app_config.dart';

class AIModelSettingsPage extends StatefulWidget {
  const AIModelSettingsPage({super.key});

  @override
  State<AIModelSettingsPage> createState() => _AIModelSettingsPageState();
}

class _AIModelSettingsPageState extends State<AIModelSettingsPage>
    with TickerProviderStateMixin {
  String? _textModel;
  String? _imageModel;
  String? _audioModel;
  String? _videoModel;
  String _provider = 'google';
  final TextEditingController _baseUrlController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> _defaultModels = [
    'gemma-3-27b-it',
    'gemma-3n-e4b-it',
    'gemini-2.5-flash-preview-09-2025',
    'gemini-2.0-flash-001',
    'gemini-robotics-er-1.5-preview',
    'gemini-2.0-flash',
    'gemini-2.0-flash-exp',
    'gemini-1.5-flash',
    'gemini-1.5-flash-8b',
  ];

  final List<String> _openRouterModels = [
    'google/gemini-2.0-flash-001',
    'google/gemini-2.0-flash-lite-preview-02-05:free',
    'google/gemini-pro-1.5',
    'anthropic/claude-3.5-sonnet',
    'openai/gpt-4o',
    'openai/gpt-4o-mini',
    'deepseek/deepseek-chat',
    'meta-llama/llama-3.1-70b-instruct',
  ];

  List<String> _customModels = [];

  List<String> get _allModels => _provider == 'google' 
      ? [..._defaultModels, ..._customModels]
      : [..._openRouterModels, ..._customModels];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));

    _loadSettings();
    _animationController.forward();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _provider = prefs.getString('global_ai_provider') ?? 'google';
      _customModels = prefs.getStringList('custom_ai_models') ?? [];
      _textModel = prefs.getString('global_text_model') ??
          prefs.getString('global_selected_model') ??
          prefs.getString('selected_model') ??
          'gemma-3-27b-it';
      _imageModel = prefs.getString('global_image_model') ??
          prefs.getString('global_selected_model') ??
          'gemini-2.5-flash-preview-09-2025';
      _audioModel = prefs.getString('global_audio_model') ??
          prefs.getString('global_selected_model') ??
          'gemini-2.5-flash-preview-09-2025';
      _videoModel = prefs.getString('global_video_model') ??
          prefs.getString('global_selected_model') ??
          'gemini-2.5-flash-preview-09-2025';
      _baseUrlController.text = prefs.getString('global_ai_base_url') ??
          'https://generativelanguage.googleapis.com/v1beta';
          
      // Safety check: ensure loaded models exist in current provider's list
      if (!_allModels.contains(_textModel)) _textModel = _allModels.first;
      if (!_allModels.contains(_imageModel)) _imageModel = _allModels.first;
      if (!_allModels.contains(_audioModel)) _audioModel = _allModels.first;
      if (!_allModels.contains(_videoModel)) _videoModel = _allModels.first;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Save all specific models
    await prefs.setString('global_text_model', _textModel ?? 'gemma-3-27b-it');
    await prefs.setString('global_image_model', _imageModel ?? 'gemini-2.5-flash-preview-09-2025');
    await prefs.setString('global_audio_model', _audioModel ?? 'gemini-2.5-flash-preview-09-2025');
    await prefs.setString('global_video_model', _videoModel ?? 'gemini-2.5-flash-preview-09-2025');
    await prefs.setString('global_ai_base_url', _baseUrlController.text.trim());
    await prefs.setStringList('custom_ai_models', _customModels);
    await prefs.setString('global_ai_provider', _provider);

    // Also update legacy ones with text model for backward compatibility
    await prefs.setString('global_selected_model', _textModel ?? 'gemma-3-27b-it');
    await prefs.setString('selected_model', _textModel ?? 'gemma-3-27b-it');

    _showSnackBar(
      content: 'AI Settings Saved Successfully!',
      icon: Icons.check_circle,
      color: Colors.green.shade600,
    );
  }

  void _showSnackBar({
    required String content,
    required IconData icon,
    required Color color,
  }) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                content,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          elevation: 8,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showAddCustomModelDialog() {
    final TextEditingController customModelController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text('Add Custom Model',
            style: TextStyle(color: colorScheme.onSurface)),
        content: TextField(
          controller: customModelController,
          autofocus: true,
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'e.g. gpt-4, claude-3-opus',
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorScheme.outline),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newModel = customModelController.text.trim();
              if (newModel.isNotEmpty) {
                if (!_allModels.contains(newModel)) {
                  setState(() {
                    _customModels.add(newModel);
                    // Automatically select it for text by default or just add it
                  });
                  Navigator.pop(context);
                  _showSnackBar(
                    content: 'Added model: $newModel',
                    icon: Icons.add_task,
                    color: Colors.blue.shade600,
                  );
                } else {
                  _showSnackBar(
                    content: 'Model already exists!',
                    icon: Icons.warning,
                    color: Colors.orange.shade700,
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Global AI Settings',
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeCard(textTheme, colorScheme),
                  const SizedBox(height: 20),
                  _buildModelSettingsCard(textTheme, colorScheme),
                  const SizedBox(height: 30),
                  _buildSaveButton(textTheme, colorScheme),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(TextTheme textTheme, ColorScheme colorScheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withAlpha((0.2 * 255).toInt()),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: colorScheme.onPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Model Preferences',
                        style: textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallScreen ? 18 : 24,
                        ),
                      ),
                      Text(
                        'Manage AI settings across the entire app',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer
                              .withAlpha((0.9 * 255).toInt()),
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedCard({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.05 * 255).toInt()),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha((0.5 * 255).toInt()),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, Color color, TextTheme textTheme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withAlpha((0.1 * 255).toInt()),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildModelSettingsCard(TextTheme textTheme, ColorScheme colorScheme) {
    return _buildAnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Model Configuration',
            Icons.memory,
            Colors.blue,
            textTheme,
          ),
          const SizedBox(height: 20),
          _buildProviderDropdown(),
          const SizedBox(height: 16),
          _buildDropdown('Text AI Model', Icons.text_fields, _textModel, (v) => setState(() => _textModel = v)),
          const SizedBox(height: 16),
          _buildDropdown('Image AI Model', Icons.image, _imageModel, (v) => setState(() => _imageModel = v)),
          const SizedBox(height: 16),
          _buildDropdown('Audio AI Model', Icons.audiotrack, _audioModel, (v) => setState(() => _audioModel = v)),
          const SizedBox(height: 16),
          _buildDropdown('Video AI Model', Icons.video_library, _videoModel, (v) => setState(() => _videoModel = v)),
          const SizedBox(height: 24),
          _buildAddCustomModelSection(textTheme, colorScheme),
          const SizedBox(height: 20),
          _buildBaseUrlField(),
          const SizedBox(height: 20),
          _buildApiKeyButton(textTheme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildAddCustomModelSection(TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Custom Models',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            IconButton(
              onPressed: _showAddCustomModelDialog,
              icon: Icon(Icons.add_circle, color: colorScheme.primary, size: 28),
              tooltip: 'Add Custom Model',
            ),
          ],
        ),
        if (_customModels.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _customModels.map((model) {
              return Chip(
                label: Text(model, style: TextStyle(color: colorScheme.onSurfaceVariant)),
                onDeleted: () {
                  setState(() {
                    _customModels.remove(model);
                    // Reset if selected
                    if (_textModel == model) _textModel = _defaultModels.first;
                    if (_imageModel == model) _imageModel = _defaultModels.first;
                    if (_audioModel == model) _audioModel = _defaultModels.first;
                    if (_videoModel == model) _videoModel = _defaultModels.first;
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: colorScheme.surfaceContainerHighest,
              );
            }).toList(),
          )
        else
          Text(
            'No custom models added yet',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildProviderDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'AI Provider',
          labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(Icons.hub, color: colorScheme.primary),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        value: _provider,
        items: const [
          DropdownMenuItem(value: 'google', child: Text('Google Gemini')),
          DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
          DropdownMenuItem(value: 'openai', child: Text('OpenAI Compatible')),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _provider = v;
              if (v == 'openrouter') {
                _baseUrlController.text = AppConfig.openRouterBaseUrl;
                _textModel = AppConfig.openRouterModelId;
                _imageModel = AppConfig.openRouterModelId;
                _audioModel = AppConfig.openRouterModelId;
                _videoModel = AppConfig.openRouterModelId;
              } else if (v == 'google') {
                _baseUrlController.text = 'https://generativelanguage.googleapis.com/v1beta';
                _textModel = 'gemma-3-27b-it';
                _imageModel = 'gemini-2.5-flash-preview-09-2025';
                _audioModel = 'gemini-2.5-flash-preview-09-2025';
                _videoModel = 'gemini-2.5-flash-preview-09-2025';
              }
            });
          }
        },
        dropdownColor: colorScheme.surfaceContainerHigh,
      ),
    );
  }

  Widget _buildBaseUrlField() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: TextFormField(
        controller: _baseUrlController,
        style: TextStyle(color: colorScheme.onSurface),
        decoration: InputDecoration(
          labelText: 'Custom Base URL',
          labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(Icons.link, color: colorScheme.primary),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, IconData icon, String? value, ValueChanged<String?> onChanged) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(icon, color: colorScheme.primary),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        value: _allModels.contains(value) ? value : null,
        items: _allModels.map((model) {
          return DropdownMenuItem<String>(
            value: model,
            child: Text(
              model,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: onChanged,
        hint: Text('Choose a $label',
            style: TextStyle(color: colorScheme.onSurfaceVariant)),
        dropdownColor: colorScheme.surfaceContainerHigh,
      ),
    );
  }

  Widget _buildApiKeyButton(TextTheme textTheme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.secondary.withAlpha((0.2 * 255).toInt()),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: () => showApiKeyDialog(context),
        icon: Icon(Icons.vpn_key, color: colorScheme.onSecondaryContainer),
        label: Text(
          'Manage API Key',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSecondaryContainer,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton(TextTheme textTheme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withAlpha((0.8 * 255).toInt())
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withAlpha((0.3 * 255).toInt()),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _saveSettings,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Save Preferences',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
