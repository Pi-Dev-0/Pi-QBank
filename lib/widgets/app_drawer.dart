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
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.bottomCenter.add(const Alignment(0, -0.15)),
                  colors: [
                    Theme.of(context).scaffoldBackgroundColor,
                    Colors.transparent,
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstOut,
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ListView(
                  primary: false,
                  padding: EdgeInsets.zero,
                  children: [
                    DrawerHeader(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).primaryColor,
                            const Color(0xFF2C5364),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Theme.of(context).primaryColor.withValues(alpha:0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha:0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.pushNamed(context, '/info');
                              },
                              child: Hero(
                                tag: 'profile_image',
                                child: CircleAvatar(
                                  radius: 32,
                                  backgroundColor:
                                      Colors.white.withValues(alpha:0.9),
                                  child: const CircleAvatar(
                                    radius: 30,
                                    backgroundImage:
                                        AssetImage('assets/images/hero.jpg'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Text(
                            'MD. Rashid Sahriar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha:0.3),
                                  offset: const Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha:0.15),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Text(
                              'Creator of Pi-Mathematics',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Consumer2<ConnectivityService, AppModeProvider>(
                      builder: (context, connectivity, appMode, _) {
                        return Container(
                          margin: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 4,
                            top: 2,
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: connectivity.isOnline
                                        ? [
                                            Colors.green.shade100,
                                            Colors.green.shade50
                                          ]
                                        : [
                                            Colors.red.shade100,
                                            Colors.red.shade50
                                          ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 500),
                                      child: Icon(
                                        connectivity.isOnline
                                            ? Icons.wifi
                                            : Icons.wifi_off,
                                        key: ValueKey(connectivity.isOnline),
                                        color: connectivity.isOnline
                                            ? Colors.green
                                            : Colors.red,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      connectivity.isOnline
                                          ? 'Connected'
                                          : 'Disconnected',
                                      style: TextStyle(
                                        color: connectivity.isOnline
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF4776E6),
                                      const Color(0xFF8E54E9),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4776E6)
                                          .withValues(alpha:0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                      spreadRadius: 0,
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF8E54E9)
                                          .withValues(alpha:0.2),
                                      blurRadius: 8,
                                      offset: const Offset(-2, -2),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(25),
                                    splashColor: Colors.white.withValues(alpha:0.2),
                                    highlightColor:
                                        Colors.white.withValues(alpha:0.1),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.pushNamed(
                                          context, '/downloaded');
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color:
                                                  Colors.white.withValues(alpha:0.2),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.download_done,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            'View Downloads',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.1),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.home),
                            title: const Text('Home'),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/');
                            },
                          ),
                          const Divider(height: 1, indent: 70, endIndent: 20),
                          ListTile(
                            leading: const Icon(Icons.bookmark),
                            title: const Text('Bookmarks'),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/bookmarks');
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.1),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
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
                                    .withValues(alpha:0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.functions),
                                    title: const Text('Formula'),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 24.0),
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
                                        .withValues(alpha:0.3),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.menu_book),
                                    title: const Text('Books'),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 24.0),
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
                                        .withValues(alpha:0.3),
                                  ),
                                  ListTile(
                                    leading:
                                        const Icon(Icons.lightbulb_outline),
                                    title: const Text('Suggestions'),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 24.0),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          bottom: Radius.circular(12)),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      Navigator.pushNamed(
                                          context, '/suggestions');
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Theme.of(context).primaryColor.withValues(alpha:0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha:0.2),
                                  Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha:0.05),
                                ],
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15),
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: -10,
                                  top: -10,
                                  child: Icon(
                                    Icons.upload_file,
                                    size: 80,
                                    color: Theme.of(context)
                                        .primaryColor
                                        .withValues(alpha:0.1),
                                  ),
                                ),
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .primaryColor
                                          .withValues(alpha:0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.upload_file,
                                      color: Theme.of(context).primaryColor,
                                      size: 30,
                                    ),
                                  ),
                                  title: Text(
                                    'Upload File',
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Share your materials',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .primaryColor
                                          .withValues(alpha:0.7),
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.arrow_forward_ios,
                                    color: Theme.of(context).primaryColor,
                                    size: 16,
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.pushNamed(context, '/upload');
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, indent: 70, endIndent: 20),
                          ListTile(
                            leading: const Icon(Icons.info),
                            title: const Text('About'),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/info');
                            },
                          ),
                          const Divider(height: 1, indent: 70, endIndent: 20),
                          ListTile(
                            leading: const Icon(Icons.help_outline),
                            title: const Text('App Manual'),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/manual');
                            },
                          ),
                          const Divider(height: 1, indent: 70, endIndent: 20),
                          ListTile(
                            leading: const Icon(Icons.share),
                            title: const Text('Tell a Friend'),
                            onTap: () {
                              Navigator.pop(context);
                              Share.share(
                                'Check out Pi-QBank App: https://pi-qbank.blogspot.com',
                                subject: 'Pi-QBank App',
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
