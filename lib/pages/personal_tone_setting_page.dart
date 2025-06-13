import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:ui'; // Import for ImageFilter
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

  final List<Map<String, dynamic>> _presetTones = [
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
      'gradient': [Colors.purple.shade300, Colors.purple.shade600],
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
      'gradient': [Colors.blue.shade300, Colors.blue.shade600],
    },
    {
      'name': 'Teacher/Professor',
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
      'gradient': [Colors.green.shade300, Colors.green.shade600],
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
      'gradient': [Colors.orange.shade300, Colors.orange.shade600],
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
    });
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'Settings Saved Successfully!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(preset['icon'], color: Colors.white),
            const SizedBox(width: 10),
            Text(
              'Preset "${preset['name']}" Applied!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: preset['color'],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        elevation: 8,
      ),
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
      body: Stack(
        children: [
          // Background with gradient
          Container(
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
          ),
          // Blur effect
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              color: Colors.white.withOpacity(0.1), // Semi-transparent overlay
            ),
          ),
          // Original content with fade and slide animations
          FadeTransition(
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard(TextTheme textTheme, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withOpacity(0.8),
                blurRadius: 15,
                offset: const Offset(0, 10),
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
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Create the perfect tone for your conversations',
                            style: textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withOpacity(0.9),
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
              return _buildPresetCard(preset, colorScheme);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(
      Map<String, dynamic> preset, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => _applyPreset(preset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: (preset['color'] ?? Colors.grey).withOpacity(0.8),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      preset['icon'] ?? Icons.star,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    preset['name'],
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13, // Reduced font size to help with overflow
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Select AI Model',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(Icons.smart_toy, color: Colors.blue.shade600),
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
                color: Colors.blue.shade800,
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
        hint: Text('Choose a model'),
        dropdownColor: Colors.blue.shade50,
      ),
    );
  }

  Widget _buildApiKeyButton(TextTheme textTheme, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withOpacity(0.8),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () => showApiKeyDialog(context),
            icon: Icon(Icons.vpn_key, color: Colors.white),
            label: Text(
              'Manage API Key',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
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
          _buildEnhancedTextField(_nameController, 'Name', 'e.g., Rashid Sahriar',
              Icons.person, Colors.green),
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
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.orange.shade100],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200, width: 2),
      ),
      child: Column(
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 48,
            color: Colors.orange.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'No custom traits added yet',
            style: textTheme.titleMedium?.copyWith(
              color: Colors.orange.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Add Custom Trait" to personalize your AI further',
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.orange.shade600,
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
        gradient: LinearGradient(
          colors: [Colors.teal.shade50, Colors.teal.shade100],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade600,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: Colors.white,
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
                    color: Colors.teal.shade700,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
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
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.label, color: Colors.teal.shade600),
                  ),
                  onChanged: (value) => trait['trait'] = value,
                  controller: TextEditingController(text: trait['trait']),
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
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.star, color: Colors.teal.shade600),
                  ),
                  onChanged: (value) => trait['value'] = value,
                  controller: TextEditingController(text: trait['value']),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.teal.withOpacity(0.8),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _addCustomTrait,
              icon: Icon(Icons.add_circle, color: Colors.white),
              label: Text(
                'Add Custom Trait',
                style: TextStyle(
                  color: Colors.white,
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
        ),
      ),
    );
  }

  Widget _buildSaveButton(TextTheme textTheme, ColorScheme colorScheme) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            width: double.infinity,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: Icon(Icons.save, color: Colors.white, size: 24),
              label: Text(
                'Save Settings',
                style: TextStyle(
                  color: Colors.white,
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
        ),
      ),
    );
  }

  Widget _buildAnimatedCard({required Widget child}) {
    return ClipRRect(
      // Clip for rounded corners with blur
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: 10.0, sigmaY: 10.0), // Blur behind the card
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2), // Translucent white
            borderRadius: BorderRadius.circular(
                20), // Redundant with ClipRRect but good for consistency
            border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5), // Subtle border
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, IconData icon, MaterialColor color, TextTheme textTheme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.shade400, color.shade600],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color.shade700,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.shade50, color.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(icon, color: color.shade600),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        style: TextStyle(color: color.shade800, fontWeight: FontWeight.w500),
      ),
    );
  }
}
