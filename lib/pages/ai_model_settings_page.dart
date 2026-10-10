import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/api_key_dialog.dart';
import '../services/ai_models_service.dart';

class AIModelSettingsPage extends StatefulWidget {
  const AIModelSettingsPage({super.key});

  @override
  State<AIModelSettingsPage> createState() => _AIModelSettingsPageState();
}

class _AIModelSettingsPageState extends State<AIModelSettingsPage>
    with TickerProviderStateMixin {
  String? _textModel;
  String? _imageModel;
  String _provider = 'google';
  final TextEditingController _baseUrlController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  List<AIModel> _allModels = [];
  List<AIModel> _googleModels = [];
  List<AIModel> _openRouterModels = [];
  List<AIModel> _openAIModels = [];
  final Map<String, String> _providerBaseUrls = {};
  bool _modelsLoading = true;

  List<String> _customModels = [];

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
    _fetchModels();
    _animationController.forward();
  }

  Future<void> _fetchModels() async {
    final models = await AIModelsService.fetchModels(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _allModels = models;
      _googleModels = models.where((m) => m.provider == 'google').toList();
      _openRouterModels =
          models.where((m) => m.provider == 'openrouter').toList();
      _openAIModels = models.where((m) => m.provider == 'openai').toList();
      _modelsLoading = false;
    });
  }

  List<AIModel> get _currentProviderModels {
    switch (_provider) {
      case 'openrouter':
        return _openRouterModels.isNotEmpty ? _openRouterModels : _googleModels;
      case 'openai':
        return _openAIModels.isNotEmpty ? _openAIModels : _googleModels;
      default:
        return _googleModels.isNotEmpty ? _googleModels : _allModels;
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _provider = prefs.getString('global_ai_provider') ?? 'google';
      _customModels = prefs.getStringList('custom_ai_models') ?? [];
      _textModel = prefs.getString('global_text_model') ??
          prefs.getString('global_selected_model') ??
          prefs.getString('selected_model') ??
          'gemini-3.8-flash';
      _imageModel = prefs.getString('global_image_model') ??
          prefs.getString('global_selected_model') ??
          'gemini-2.5-flash';
      _baseUrlController.text = prefs.getString('global_ai_base_url') ??
          'https://generativelanguage.googleapis.com/v1beta';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('global_text_model', _textModel ?? 'gemini-3.8-flash');
    await prefs.setString('global_image_model', _imageModel ?? 'gemini-2.5-flash');
    await prefs.setString('global_ai_base_url', _baseUrlController.text.trim());
    await prefs.setStringList('custom_ai_models', _customModels);
    await prefs.setString('global_ai_provider', _provider);
    await prefs.setString('global_selected_model', _textModel ?? 'gemini-3.8-flash');
    await prefs.setString('selected_model', _textModel ?? 'gemini-3.8-flash');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text('AI Settings Saved!',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _showAddCustomModelDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Custom Model'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. gpt-4, claude-3-opus',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final m = controller.text.trim();
              if (m.isNotEmpty && !_customModels.contains(m)) {
                setState(() => _customModels.add(m));
                Navigator.pop(ctx);
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(title: 'AI & API Settings', centerTitle: true),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProviderCard(cs),
                const SizedBox(height: 16),
                _buildModelCards(cs),
                const SizedBox(height: 16),
                _buildApiConfigCard(cs),
                const SizedBox(height: 24),
                _buildSaveButton(cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProviderCard(ColorScheme cs) {
    return _card([
      _header('AI Provider', Icons.hub, cs.primary, cs),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _providerChip('google', 'Google', Icons.g_mobiledata, cs),
          _providerChip('openrouter', 'OpenRouter', Icons.cloud, cs),
          _providerChip('openai', 'OpenAI', Icons.smart_toy, cs),
        ],
      ),
      if (_providerBaseUrls.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.link, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _providerBaseUrls[_provider] ?? _baseUrlController.text,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _providerChip(
      String value, String label, IconData icon, ColorScheme cs) {
    final selected = _provider == value;
    return ChoiceChip(
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : cs.primary),
      label: Text(label),
      selected: selected,
      selectedColor: cs.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : cs.onSurface,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() {
          _provider = value;
          final base = _providerBaseUrls[value];
          if (base != null) _baseUrlController.text = base;
          final models = _currentProviderModels;
          if (models.isNotEmpty) {
            _textModel = models.first.id;
            _imageModel = models.first.id;
          }
        });
      },
    );
  }

  Widget _buildModelCards(ColorScheme cs) {
    return _card([
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _header('Models', Icons.memory, Colors.blue, cs),
          IconButton(
            tooltip: 'Refresh models',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _fetchModels,
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_modelsLoading)
        const Center(
            child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
            ))
      else ...[
        _modelDropdown('Text Model', Icons.text_fields, _textModel, (v) {
          setState(() => _textModel = v);
        }, cs),
        const SizedBox(height: 12),
        _modelDropdown('Image Model', Icons.image, _imageModel, (v) {
          setState(() => _imageModel = v);
        }, cs),
        const SizedBox(height: 16),
        _buildCustomModels(cs),
      ],
    ]);
  }

  Widget _modelDropdown(String label, IconData icon, String? value,
      ValueChanged<String?> onChanged, ColorScheme cs) {
    final models = _currentProviderModels;
    final effectiveValue = models.any((m) => m.id == value) ? value : null;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: cs.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          ),
          value: effectiveValue,
          items: models
              .map((m) => DropdownMenuItem(
                    value: m.id,
                    child: Text(m.displayName.isNotEmpty ? m.displayName : m.id,
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
          dropdownColor: cs.surfaceContainerHigh,
        ),
      ),
    );
  }

  Widget _buildCustomModels(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Custom Models',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: cs.onSurface)),
            IconButton(
              onPressed: _showAddCustomModelDialog,
              icon: Icon(Icons.add_circle, color: cs.primary),
              iconSize: 24,
            ),
          ],
        ),
        if (_customModels.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _customModels
                .map((m) => Chip(
                      label: Text(m),
                      onDeleted: () =>
                          setState(() => _customModels.remove(m)),
                      backgroundColor: cs.surfaceContainerHighest,
                    ))
                .toList(),
          )
        else
          Text('No custom models yet',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }

  Widget _buildApiConfigCard(ColorScheme cs) {
    return _card([
      _header('API Configuration', Icons.vpn_key, Colors.orange, cs),
      const SizedBox(height: 12),
      TextField(
        controller: _baseUrlController,
        decoration: InputDecoration(
          labelText: 'Base URL',
          prefixIcon: Icon(Icons.link, color: cs.primary),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => showApiKeyDialog(context),
          icon: const Icon(Icons.key),
          label: const Text('Manage API Key'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  Widget _buildSaveButton(ColorScheme cs) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: [cs.primary, cs.primary.withAlpha(204)]),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withAlpha(77),
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
                borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Save Preferences',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withAlpha(128)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _header(String title, IconData icon, Color color, ColorScheme cs) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: cs.onSurface)),
      ],
    );
  }
}
