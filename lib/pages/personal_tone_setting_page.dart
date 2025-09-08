import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/custom_app_bar.dart';
import '../widgets/api_key_dialog.dart';

class PersonalToneSettingPage extends StatefulWidget {
  const PersonalToneSettingPage({super.key});

  @override
  State<PersonalToneSettingPage> createState() =>
      _PersonalToneSettingPageState();
}

class _PersonalToneSettingPageState extends State<PersonalToneSettingPage>
    with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  final List<Map<String, String>> _customTraits = [];
  String? _selectedModel;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<String> _availableModels = [
    'gemma-3-27b-it',
    'gemma-3n-e4b-it',
    'gemini-1.5-flash-8b',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-2.0-flash-lite',
    'gemini-2.0-flash',
    'gemini-2.0-flash-preview-image-generation',
    'gemini-2.5-flash-preview-05-20',
  ];

  List<Map<String, dynamic>> _presetTones = [];
  List<Map<String, dynamic>> _customSavedPresets = [];

  final List<Map<String, dynamic>> _defaultPresetTones = [
    {
      'name': 'Custom Tone',
      'gender': '',
      'relationship': '',
      'language': '',
      'purpose': '',
      'customTraits': [],
      'isCustom': true,
      'icon': Icons.palette,
      'color': Colors.purple,
    },
    {
      'name': 'AI Assistant',
      'gender': 'Neutral',
      'relationship': 'Assistant',
      'language': 'English',
      'purpose': 'General assistance, information retrieval, task automation',
      'customTraits': [
        {'trait': 'Formality', 'value': 'Formal'},
        {'trait': 'Empathy', 'value': 'High'},
        {'trait': 'Conciseness', 'value': 'High'},
      ],
      'icon': Icons.smart_toy,
      'color': Colors.blue,
    },
    {
      'name': 'Teacher',
      'gender': 'Neutral',
      'relationship': 'Educator',
      'language': 'English',
      'purpose': 'Instruction, explanation, guidance, knowledge sharing',
      'customTraits': [
        {'trait': 'Formality', 'value': 'Academic'},
        {'trait': 'Authority', 'value': 'High'},
        {'trait': 'Clarity', 'value': 'High'},
      ],
      'icon': Icons.school,
      'color': Colors.green,
    },
    {
      'name': 'Friend',
      'gender': 'Neutral',
      'relationship': 'Friend',
      'language': 'English',
      'purpose': 'Casual conversation, emotional support, companionship',
      'customTraits': [
        {'trait': 'Formality', 'value': 'Informal'},
        {'trait': 'Humor', 'value': 'Moderate'},
        {'trait': 'Empathy', 'value': 'High'},
      ],
      'icon': Icons.favorite,
      'color': Colors.orange,
    },
  ];

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
      _nameController.text = prefs.getString('tone_name') ?? '';
      _genderController.text = prefs.getString('tone_gender') ?? '';
      _relationshipController.text = prefs.getString('tone_relationship') ?? '';
      _languageController.text = prefs.getString('tone_language') ?? '';
      _purposeController.text = prefs.getString('tone_purpose') ?? '';

      final customTraitsJson = prefs.getStringList('tone_customTraits');
      if (customTraitsJson != null) {
        _customTraits.clear();
        for (var jsonString in customTraitsJson) {
          _customTraits.add(Map<String, String>.from(jsonDecode(jsonString)));
        }
      }
      _selectedModel =
          prefs.getString('selected_model') ?? 'gemini-2.5-flash-preview-05-20';

      // Load custom saved presets
      final savedPresetsJson = prefs.getStringList('custom_saved_presets');
      if (savedPresetsJson != null) {
        _customSavedPresets = savedPresetsJson
            .map((jsonString) => jsonDecode(jsonString) as Map<String, dynamic>)
            .toList();
      }
      _updatePresetTonesList();
    });
  }

  void _updatePresetTonesList() {
    _presetTones = [..._defaultPresetTones, ..._customSavedPresets];
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tone_name', _nameController.text);
    await prefs.setString('tone_gender', _genderController.text);
    await prefs.setString('tone_relationship', _relationshipController.text);
    await prefs.setString('tone_language', _languageController.text);
    await prefs.setString('tone_purpose', _purposeController.text);
    await prefs.setString(
        'selected_model', _selectedModel ?? 'gemini-2.5-flash-preview-05-20');

    final customTraitsJson =
        _customTraits.map((trait) => jsonEncode(trait)).toList();
    await prefs.setStringList('tone_customTraits', customTraitsJson);

    _showSnackBar(
      content: 'Settings Saved Successfully!',
      icon: Icons.check_circle,
      color: Colors.green.shade600,
    );
  }

  Future<void> _saveCustomPreset(String presetName) async {
    if (presetName.trim().isEmpty) {
      _showSnackBar(
        content: 'Preset name cannot be empty!',
        icon: Icons.error,
        color: Colors.red.shade600,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final newPreset = {
      'name': presetName,
      'gender': _genderController.text,
      'relationship': _relationshipController.text,
      'language': _languageController.text,
      'purpose': _purposeController.text,
      'customTraits': _customTraits,
      'isCustom': true,
      'icon': Icons.bookmark, // A distinct icon for user-saved presets
      'color': Colors.deepPurple,
    };

    setState(() {
      _customSavedPresets.add(newPreset);
      _updatePresetTonesList();
    });

    final savedPresetsJson =
        _customSavedPresets.map((preset) => jsonEncode(preset)).toList();
    await prefs.setStringList('custom_saved_presets', savedPresetsJson);

    _showSnackBar(
      content: 'Preset "$presetName" Saved!',
      icon: Icons.bookmark_added,
      color: Colors.deepPurple.shade600,
    );
  }

  Future<void> _deleteCustomPreset(String presetName) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customSavedPresets.removeWhere((preset) => preset['name'] == presetName);
      _updatePresetTonesList();
    });

    final savedPresetsJson =
        _customSavedPresets.map((preset) => jsonEncode(preset)).toList();
    await prefs.setStringList('custom_saved_presets', savedPresetsJson);

    _showSnackBar(
      content: 'Preset "$presetName" Deleted!',
      icon: Icons.delete_forever,
      color: Colors.red.shade600,
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
                style: TextStyle(
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

  void _addCustomTrait() {
    setState(() {
      _customTraits.add({'trait': '', 'value': ''});
    });
  }

  void _removeCustomTrait(int index) {
    setState(() {
      _customTraits.removeAt(index);
    });
  }

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      _nameController.text = preset['name'] ?? '';
      _genderController.text = preset['gender'] ?? '';
      _relationshipController.text = preset['relationship'] ?? '';
      _languageController.text = preset['language'] ?? '';
      _purposeController.text = preset['purpose'] ?? '';

      _customTraits.clear();
      if (preset['customTraits'] != null) {
        for (var trait in preset['customTraits']) {
          _customTraits.add(Map<String, String>.from(trait));
        }
      }

      if (preset['isCustom'] == true) {
        _nameController.clear();
        _genderController.clear();
        _relationshipController.clear();
        _languageController.clear();
        _purposeController.clear();
        _customTraits.clear();
      }
    });

    _showSnackBar(
      content: 'Preset "${preset['name']}" Applied!',
      icon: preset['icon'],
      color: preset['color'],
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _genderController.dispose();
    _relationshipController.dispose();
    _languageController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Personal Tone Settings',
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
                  _buildPresetTonesCard(textTheme, colorScheme),
                  const SizedBox(height: 20),
                  _buildModelSettingsCard(textTheme, colorScheme),
                  const SizedBox(height: 20),
                  _buildBasicInfoCard(textTheme, colorScheme),
                  const SizedBox(height: 20),
                  _buildCustomTraitsCard(textTheme, colorScheme),
                  const SizedBox(height: 30),
                  _buildSaveButton(textTheme, colorScheme),
                  const SizedBox(height: 20),
                  _buildSavePresetButton(textTheme, colorScheme),
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer, // Use a theme-appropriate color
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.2),
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
                        'Personalize Your AI',
                        style: textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Create the perfect tone for your conversations',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer.withOpacity(0.9),
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

  Widget _buildPresetTonesCard(TextTheme textTheme, ColorScheme colorScheme) {
    return _buildAnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Preset Tones',
            Icons.palette,
            Colors.purple,
            textTheme,
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2, // Increased further to fix overflow
            ),
            itemCount: _presetTones.length,
            itemBuilder: (context, index) {
              final preset = _presetTones[index];
              return _buildPresetCard(preset, colorScheme,
                  isCustomSaved: preset['isCustom'] == true &&
                      preset['icon'] == Icons.bookmark);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(Map<String, dynamic> preset, ColorScheme colorScheme,
      {bool isCustomSaved = false}) {
    final Color cardColor = (preset['color'] as Color? ?? Colors.grey);
    return GestureDetector(
      onTap: () => _applyPreset(preset),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: cardColor.withOpacity(0.1), // Lighter background
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardColor.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: cardColor.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      preset['icon'] ?? Icons.star,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Text(
                      preset['name'],
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14, // Slightly increased font size
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (isCustomSaved)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () =>
                      _showDeletePresetDialog(context, preset['name']),
                  child: Icon(
                    Icons.delete,
                    color: Colors.red.shade400,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSettingsCard(TextTheme textTheme, ColorScheme colorScheme) {
    return _buildAnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Model Settings',
            Icons.memory,
            Colors.blue,
            textTheme,
          ),
          const SizedBox(height: 20),
          _buildEnhancedDropdown(),
          const SizedBox(height: 20),
          _buildApiKeyButton(textTheme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildEnhancedDropdown() {
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
          labelText: 'Select AI Model',
          labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(Icons.smart_toy, color: colorScheme.primary),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        value: _selectedModel,
        items: _availableModels.map((model) {
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
        onChanged: (selectedModel) {
          setState(() {
            _selectedModel = selectedModel;
          });
        },
        hint: Text('Choose a model', style: TextStyle(color: colorScheme.onSurfaceVariant)),
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
            color: colorScheme.secondary.withOpacity(0.2),
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

  Widget _buildBasicInfoCard(TextTheme textTheme, ColorScheme colorScheme) {
    return _buildAnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Basic Information',
            Icons.person,
            Colors.green,
            textTheme,
          ),
          const SizedBox(height: 20),
          _buildEnhancedTextField(_nameController, 'Name',
              'e.g., Rashid Sahriar', Icons.person, Colors.green),
          _buildEnhancedTextField(_genderController, 'Gender',
              'e.g., Male, Female, Non-binary', Icons.transgender, Colors.pink),
          _buildEnhancedTextField(_relationshipController, 'Relationship',
              'e.g., Friend, Colleague, Family', Icons.people, Colors.orange),
          _buildEnhancedTextField(_languageController, 'Language',
              'e.g., English, Spanish, Bengali', Icons.language, Colors.blue),
          _buildEnhancedTextField(
              _purposeController,
              'Purpose',
              'e.g., Education, Entertainment, Business',
              Icons.lightbulb_outline,
              Colors.purple),
        ],
      ),
    );
  }

  Widget _buildCustomTraitsCard(TextTheme textTheme, ColorScheme colorScheme) {
    return _buildAnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Custom Traits',
            Icons.tune,
            Colors.orange,
            textTheme,
          ),
          const SizedBox(height: 20),
          if (_customTraits.isEmpty)
            _buildEmptyTraitsMessage(textTheme, colorScheme)
          else
            ..._customTraits.asMap().entries.map((entry) {
              int index = entry.key;
              Map<String, String> trait = entry.value;
              return _buildCustomTraitRow(index, trait, colorScheme);
            }),
          const SizedBox(height: 20),
          _buildAddTraitButton(colorScheme),
        ],
      ),
    );
  }

  Widget _buildEmptyTraitsMessage(
      TextTheme textTheme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
      ),
      child: Column(
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No custom traits added yet',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Add Custom Trait" to personalize your AI further',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTraitRow(
      int index, Map<String, String> trait, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: colorScheme.onTertiary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Custom Trait ${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                onPressed: () => _removeCustomTrait(index),
                tooltip: 'Remove Trait',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Trait Name',
                    hintText: 'e.g., Favorite Color',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                    prefixIcon: Icon(Icons.label, color: colorScheme.primary),
                  ),
                  onChanged: (value) => trait['trait'] = value,
                  controller: TextEditingController(text: trait['trait']),
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Trait Value',
                    hintText: 'e.g., Blue',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                    prefixIcon: Icon(Icons.star, color: colorScheme.primary),
                  ),
                  onChanged: (value) => trait['value'] = value,
                  controller: TextEditingController(text: trait['value']),
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddTraitButton(ColorScheme colorScheme) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colorScheme.tertiary.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _addCustomTrait,
          icon: Icon(Icons.add_circle, color: colorScheme.onTertiaryContainer),
          label: Text(
            'Add Custom Trait',
            style: TextStyle(
              color: colorScheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildSaveButton(TextTheme textTheme, ColorScheme colorScheme) {
    return Center(
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _saveSettings,
          icon: Icon(Icons.save, color: colorScheme.onPrimary, size: 24),
          label: Text(
            'Save Current Tone',
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavePresetButton(TextTheme textTheme, ColorScheme colorScheme) {
    return Center(
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: colorScheme.secondary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.secondary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: () => _showSavePresetDialog(context),
          icon: Icon(Icons.bookmark_add, color: colorScheme.onSecondary, size: 24),
          label: Text(
            'Save as New Preset',
            style: TextStyle(
              color: colorScheme.onSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  void _showSavePresetDialog(BuildContext context) {
    final TextEditingController presetNameController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Save Current Tone as Preset',
            style: textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: presetNameController,
            decoration: InputDecoration(
              hintText: 'Enter preset name',
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: TextStyle(color: colorScheme.onSurface),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                _saveCustomPreset(presetNameController.text);
                Navigator.of(context).pop();
              },
              child: Text(
                'Save',
                style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePresetDialog(BuildContext context, String presetName) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Delete Preset',
            style: textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "$presetName"?',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                _deleteCustomPreset(presetName);
                Navigator.of(context).pop();
              },
              child: Text(
                'Delete',
                style: TextStyle(color: colorScheme.onError, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedCard({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, // Use theme's card color
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: child,
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, MaterialColor color, TextTheme textTheme) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: colorScheme.onPrimary, size: 24),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedTextField(
    TextEditingController controller,
    String label,
    String hintText,
    IconData icon,
    MaterialColor color,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
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
        style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w500),
      ),
    );
  }
}
