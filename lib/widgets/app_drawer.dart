import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../providers/app_mode_provider.dart';
import '../services/connectivity_service.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: AssetImage('assets/images/hero.jpg'),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'MD. Rashid Sahriar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                      Text(
                        'Creator of Pi-Mathematics',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Consumer2<ConnectivityService, AppModeProvider>(
                  builder: (context, connectivity, appMode, _) {
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: connectivity.isOnline
                              ? [Colors.green.shade50, Colors.blue.shade50]
                              : [Colors.red.shade50, Colors.orange.shade50],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: connectivity.isOnline
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 500),
                                  child: Icon(
                                    connectivity.isOnline
                                        ? Icons.wifi
                                        : Icons.wifi_off,
                                    key: ValueKey(connectivity.isOnline),
                                    color: connectivity.isOnline
                                        ? Colors.green
                                        : Colors.red,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  connectivity.isOnline
                                      ? 'Connected'
                                      : 'Disconnected',
                                  style: TextStyle(
                                    color: connectivity.isOnline
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: 16, left: 16, right: 16),
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pushNamed(context, '/downloaded');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                elevation: 4,
                                shadowColor: Theme.of(context)
                                    .primaryColor
                                    .withOpacity(0.4),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.download_done,
                                    size: 20,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'View Downloads',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text('Home'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: const Text('Bookmarks'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/bookmarks');
                  },
                ),
                ExpansionTile(
                  leading: const Icon(Icons.library_books),
                  title: const Text('Study Materials'),
                  shape: const RoundedRectangleBorder(
                    side: BorderSide.none,
                  ),
                  collapsedShape: const RoundedRectangleBorder(
                    side: BorderSide.none,
                  ),
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.functions),
                            title: const Text('Formula'),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 24.0),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(12)),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/formula');
                            },
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: 24,
                            endIndent: 24,
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.3),
                          ),
                          ListTile(
                            leading: const Icon(Icons.menu_book),
                            title: const Text('Books'),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 24.0),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(12)),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/books');
                            },
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: 24,
                            endIndent: 24,
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.3),
                          ),
                          ListTile(
                            leading: const Icon(Icons.lightbulb_outline),
                            title: const Text('Suggestions'),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 24.0),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(12)),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/suggestions');
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Upload File'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/upload');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('About'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/info');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('App Manual'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/manual');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Tell a Friend'),
                  onTap: () {
                    Navigator.pop(context);
                    Share.share(
                      'Check out Pi-Mathematics App: https://pi-mathematics.blogspot.com/p/our-app.html',
                      subject: 'Pi-Mathematics App',
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.facebook, color: Colors.blue),
                  onPressed: () =>
                      _launchUrl('https://facebook.com/rashidsahriar.asif'),
                ),
                IconButton(
                  icon: const Icon(Icons.telegram, color: Colors.blue),
                  onPressed: () => _launchUrl('https://t.me/your-channel'),
                ),
                IconButton(
                  icon: const Icon(Icons.rss_feed, color: Colors.orange),
                  onPressed: () =>
                      _launchUrl('https://pi-mathematics.blogspot.com'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
