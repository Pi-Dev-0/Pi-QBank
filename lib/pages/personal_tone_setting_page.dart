import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/custom_app_bar.dart';

class PersonalToneSettingPage extends StatefulWidget {
  const PersonalToneSettingPage({super.key});

  @override
  State<PersonalToneSettingPage> createState() =>
      _PersonalToneSettingPageState();
}

class _PersonalToneSettingPageState extends State<PersonalToneSettingPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  final List<Map<String, String>> _customTraits = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tone_name', _nameController.text);
    await prefs.setString('tone_gender', _genderController.text);
    await prefs.setString('tone_relationship', _relationshipController.text);
    await prefs.setString('tone_language', _languageController.text);
    await prefs.setString('tone_purpose', _purposeController.text);

    final customTraitsJson =
        _customTraits.map((trait) => jsonEncode(trait)).toList();
    await prefs.setStringList('tone_customTraits', customTraitsJson);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settings Saved Successfully!',
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
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

  @override
  void dispose() {
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
      appBar: CustomAppBar(
        title: 'Personal Tone Settings',
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0), // Increased padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 6, // Increased elevation
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(16)), // Slightly more rounded
              margin: const EdgeInsets.only(bottom: 25), // Increased margin
              child: Padding(
                padding: const EdgeInsets.all(20.0), // Increased padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Basic Information',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600, // Semi-bold
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20), // Increased spacing
                    _buildTextField(_nameController, 'Name', 'e.g., John Doe',
                        Icons.person),
                    _buildTextField(_genderController, 'Gender',
                        'e.g., Male, Female, Non-binary', Icons.transgender),
                    _buildTextField(_relationshipController, 'Relationship',
                        'e.g., Friend, Colleague, Family', Icons.people),
                    _buildTextField(_languageController, 'Language',
                        'e.g., English, Spanish, Bengali', Icons.language),
                    _buildTextField(
                        _purposeController,
                        'Purpose',
                        'e.g., Education, Entertainment, Business',
                        Icons.lightbulb_outline),
                  ],
                ),
              ),
            ),
            Card(
              elevation: 6, // Increased elevation
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(16)), // Slightly more rounded
              margin: const EdgeInsets.only(bottom: 25), // Increased margin
              child: Padding(
                padding: const EdgeInsets.all(20.0), // Increased padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom Traits',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600, // Semi-bold
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20), // Increased spacing
                    if (_customTraits.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 15.0), // Increased padding
                        child: Text(
                          'No custom traits added yet. Click "Add Custom Trait" to add one.',
                          style: textTheme.bodyLarge?.copyWith(
                            // Changed to bodyLarge
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ..._customTraits.asMap().entries.map((entry) {
                      int index = entry.key;
                      Map<String, String> trait = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 15.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Trait ${index + 1}',
                                  hintText: 'e.g., Favorite Color',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          8.0)), // Less rounded
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerLowest,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                      horizontal: 12), // Adjusted padding
                                ),
                                onChanged: (value) => trait['trait'] = value,
                                controller:
                                    TextEditingController(text: trait['trait']),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Value ${index + 1}',
                                  hintText: 'e.g., Blue',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          8.0)), // Less rounded
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerLowest,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                      horizontal: 12), // Adjusted padding
                                ),
                                onChanged: (value) => trait['value'] = value,
                                controller:
                                    TextEditingController(text: trait['value']),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: colorScheme.error), // Changed icon
                              onPressed: () => _removeCustomTrait(index),
                              tooltip: 'Remove Trait',
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 15), // Adjusted spacing
                    Center(
                      child: TextButton.icon(
                        // Changed to TextButton.icon
                        onPressed: _addCustomTrait,
                        icon: Icon(Icons.add_circle_outline,
                            color:
                                colorScheme.primary), // Icon with primary color
                        label: Text(
                          'Add Custom Trait',
                          style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme
                                  .primary), // Text with primary color
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                                color: colorScheme.primary
                                    .withOpacity(0.5)), // Subtle border
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30), // Increased spacing before save button
            Center(
              child: ElevatedButton(
                onPressed: _saveSettings, // Call _saveSettings
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      colorScheme.primary, // Primary color for save button
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 50, vertical: 18), // Larger padding
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // More rounded
                  ),
                  textStyle: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold), // Larger and bolder text
                  elevation: 8, // More elevation for save button
                ),
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      String hintText, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18.0), // Adjusted padding
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0)), // Less rounded
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          prefixIcon: Icon(icon,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant), // Added prefix icon
          contentPadding: const EdgeInsets.symmetric(
              vertical: 15, horizontal: 12), // Adjusted padding
        ),
      ),
    );
  }
}
