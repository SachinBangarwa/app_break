import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/screens/device_apps_screen.dart';
import 'package:testproject/screens/notifications_screen.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  void _openAllAppsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AllAppsSearchBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Overview',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.black,
                      size: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Track screen time, manage app limits, and search installed applications.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),

              // Section 1: Features & Links
              const Text(
                'QUICK ACCESS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF555555),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18.0),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    // Link 1: Device Apps Screen Time Usage
                    _buildOverviewTile(
                      icon: Icons.bar_chart_rounded,
                      title: 'App Usage & Screen Time',
                      subtitle: 'View detailed daily usage stats and limits',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeviceAppsScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF3F4F6),
                      indent: 64,
                    ),

                    // Link 2: All Applications Search Bottom Sheet
                    _buildOverviewTile(
                      icon: Icons.grid_view_rounded,
                      title: 'All Applications',
                      subtitle: 'Search and launch any installed app',
                      onTap: () => _openAllAppsBottomSheet(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Icon(icon, color: Colors.black87, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF888888),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// All Apps Search Bottom Sheet Modal
class _AllAppsSearchBottomSheet extends StatefulWidget {
  const _AllAppsSearchBottomSheet();

  @override
  State<_AllAppsSearchBottomSheet> createState() =>
      _AllAppsSearchBottomSheetState();
}

class _AllAppsSearchBottomSheetState extends State<_AllAppsSearchBottomSheet> {
  List<AppInfo> _allApps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    final apps = await AppDbHelper.instance.getApps(excludeSystemApps: false);
    if (mounted) {
      setState(() {
        _allApps = apps;
        _filteredApps = apps;
        _isLoading = false;
      });
    }
  }

  void _filterApps(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredApps = _allApps;
      });
    } else {
      final q = query.trim().toLowerCase();
      setState(() {
        _filteredApps =
            _allApps
                .where(
                  (app) =>
                      app.name.toLowerCase().contains(q) ||
                      app.packageName.toLowerCase().contains(q),
                )
                .toList();
      });
    }
  }

  void _showAppOptions(BuildContext context, AppInfo app) async {
    bool isFav = await AppDbHelper.instance.isAppFavorite(app.packageName);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Header
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: app.icon != null && app.icon!.isNotEmpty
                              ? Image.memory(app.icon!, fit: BoxFit.cover)
                              : const Icon(Icons.android_rounded),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                app.packageName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: Colors.black),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    const SizedBox(height: 8),

                    // Option 1: Favorite Toggle
                    ListTile(
                      leading: Icon(
                        isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: isFav ? Colors.amber : Colors.black,
                      ),
                      title: Text(
                        isFav ? 'Remove from Favorites' : 'Add to Favorites',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () async {
                        final newFav = !isFav;
                        await AppDbHelper.instance.updateFavoriteStatus(app.packageName, newFav);
                        setModalState(() {
                          isFav = newFav;
                        });
                      },
                    ),

                    // Option 2: Open App
                    ListTile(
                      leading: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                      title: const Text('Open App', style: TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        InstalledApps.startApp(app.packageName);
                      },
                    ),

                    // Option 3: System App Settings
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, color: Colors.black),
                      title: const Text('System App Settings', style: TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(ctx);
                        InstalledApps.openSettings(app.packageName);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Handle Bar
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Header & Close Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'All Applications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF8E8E93),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _filterApps,
                        decoration: const InputDecoration(
                          hintText: 'Search apps...',
                          hintStyle: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _filterApps('');
                        },
                        child: const Icon(
                          Icons.clear_rounded,
                          color: Colors.grey,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Apps Grid List
            Expanded(
              child:
                  _isLoading
                      ? const Center(
                        child: CircularProgressIndicator(color: Colors.black),
                      )
                      : _filteredApps.isEmpty
                      ? const Center(
                        child: Text(
                          'No applications match your search',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      )
                      : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20.0,
                          vertical: 8.0,
                        ),
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 16,
                              childAspectRatio: 0.75,
                            ),
                        itemCount: _filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              InstalledApps.startApp(app.packageName);
                            },
                            onLongPress: () => _showAppOptions(context, app),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(14.0),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child:
                                      app.icon != null && app.icon!.isNotEmpty
                                          ? Image.memory(
                                            app.icon!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (_, __, ___) => const Icon(
                                                  Icons.android_rounded,
                                                  color: Colors.black87,
                                                ),
                                          )
                                          : const Icon(
                                            Icons.android_rounded,
                                            color: Colors.black87,
                                          ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  app.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
