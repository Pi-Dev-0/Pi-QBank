import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ai_page.dart';

/// Wraps [AIPage] (built-in AI chat) together with launcher cards for
/// Google Gemini and ChatGPT. The web AI tabs open in an in-app browser
/// so the user's existing browser login session is reused — no re-login needed.
class AiHubPage extends StatefulWidget {
  const AiHubPage({super.key});

  @override
  State<AiHubPage> createState() => _AiHubPageState();
}

class _AiHubPageState extends State<AiHubPage> {
  int _selectedTab = 0; // 0 = Pi AI, 1 = Gemini, 2 = ChatGPT

  // ─── Web tabs definition ──────────────────────────────────────────────────
  static const _webTabs = [
    _WebTabConfig(
      label: 'Gemini',
      tagline: 'Google AI',
      description:
          'Chat with Google\'s most capable AI. Uses your existing Google account from your browser — no separate login needed.',
      url: 'https://gemini.google.com',
      icon: Icons.auto_awesome,
      gradient: [Color(0xFF4285F4), Color(0xFF34A853)],
      features: ['Multimodal (text, image, code)', 'Google account login', 'Gemini 2.0 & Ultra'],
    ),
    _WebTabConfig(
      label: 'ChatGPT',
      tagline: 'OpenAI',
      description:
          'Chat with OpenAI\'s GPT-4o and beyond. Opens in a secure browser tab so your OpenAI session is automatically carried over.',
      url: 'https://chatgpt.com',
      icon: Icons.chat_bubble_outline_rounded,
      gradient: [Color(0xFF10a37f), Color(0xFF1a7f64)],
      features: ['GPT-4o', 'Image generation (DALL·E)', 'OpenAI account login'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Tab bar ──────────────────────────────────────────────────────
          _AiTabBar(
            selectedIndex: _selectedTab,
            onTabChanged: (i) => setState(() => _selectedTab = i),
            webTabs: _webTabs,
          ),
          // ── Tab content ──────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                // Tab 0 – Built-in Pi AI chat
                const AIPage(),
                // Tabs 1+ – Chrome launcher cards
                for (final tab in _webTabs) _WebLauncherCard(config: tab),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab bar ──────────────────────────────────────────────────────────────────

class _AiTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final List<_WebTabConfig> webTabs;

  const _AiTabBar({
    required this.selectedIndex,
    required this.onTabChanged,
    required this.webTabs,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    final tabs = [
      _TabDef(
        label: 'Pi AI',
        icon: Icons.smart_toy_outlined,
        gradient: [const Color(0xFFE84393), const Color(0xFFAD7BFF)],
      ),
      ...webTabs.map((t) => _TabDef(
            label: t.label,
            icon: t.icon,
            gradient: t.gradient,
          )),
    ];

    return Container(
      color: colorScheme.surface,
      padding: EdgeInsets.only(
        top: topPadding + 8,
        left: 12,
        right: 12,
        bottom: 8,
      ),
      child: Row(
        children: [
          for (int i = 0; i < tabs.length; i++) ...[
            Expanded(
              child: _TabChip(
                def: tabs[i],
                isSelected: selectedIndex == i,
                onTap: () => onTabChanged(i),
              ),
            ),
            if (i < tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  const _TabDef({required this.label, required this.icon, required this.gradient});
}

class _TabChip extends StatelessWidget {
  final _TabDef def;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabChip({
    required this.def,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: isSelected
            ? LinearGradient(
                colors: def.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isSelected ? null : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: def.gradient.first.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                def.icon,
                size: 16,
                color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                def.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Browser launcher card ─────────────────────────────────────────────────────

class _WebLauncherCard extends StatelessWidget {
  final _WebTabConfig config;

  const _WebLauncherCard({required this.config});

  Future<void> _launch(BuildContext context) async {
    final uri = Uri.parse(config.url);
    try {
      // First try to open in an in-app browser (like Chrome Custom Tabs)
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched) {
        // If that fails, fallback to opening the external browser app
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the browser. Please check your browser app.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero gradient card ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: config.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: config.gradient.first.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon + badge
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(config.icon, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            config.tagline,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    config.description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Feature pills ─────────────────────────────────────────────
            Text(
              'What you get',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: config.features
                  .map(
                    (f) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: config.gradient.first.withOpacity(
                            isDark ? 0.2 : 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: config.gradient.first.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 14,
                              color: config.gradient.first),
                          const SizedBox(width: 6),
                          Text(
                            f,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 28),

            // ── How login works info box ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.blue.shade100,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18,
                      color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Opens in your browser. If you\'re already signed in to ${config.label} on your device, you\'ll be taken directly to the chat — no password needed.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: isDark
                            ? Colors.blue.shade200
                            : Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Launch button ─────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: config.gradient,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: config.gradient.first.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _launch(context),
                  icon: const Icon(Icons.open_in_browser_rounded,
                      color: Colors.white),
                  label: Text(
                    'Open ${config.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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

            const SizedBox(height: 16),

            // URL hint
            Center(
              child: Text(
                config.url,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Config ───────────────────────────────────────────────────────────────────

class _WebTabConfig {
  final String label;
  final String tagline;
  final String description;
  final String url;
  final IconData icon;
  final List<Color> gradient;
  final List<String> features;

  const _WebTabConfig({
    required this.label,
    required this.tagline,
    required this.description,
    required this.url,
    required this.icon,
    required this.gradient,
    required this.features,
  });
}
