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
                    return ListTile(
                      leading: Icon(
                        connectivity.isOnline ? Icons.wifi : Icons.wifi_off,
                        color:
                            connectivity.isOnline ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      title: Text(
                        connectivity.isOnline ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color:
                              connectivity.isOnline ? Colors.green : Colors.red,
                          fontSize: 14,
                        ),
                      ),
                      trailing: ElevatedButton.icon(
                        icon: const Icon(Icons.download_done, size: 16),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/downloaded');
                        },
                        label: const Text(
                          'Downloads',
                          style: TextStyle(fontSize: 12),
                        ),
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
                            leading: const Icon(Icons.library_books),
                            title: const Text('Guides'),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 24.0),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/guides');
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
