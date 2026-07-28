import 'package:flutter/material.dart';
import 'package:testproject/device_app/localSaver/custom_app_model.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';

class ConfiguredAppsScreen extends StatefulWidget {
  const ConfiguredAppsScreen({super.key});

  @override
  State<ConfiguredAppsScreen> createState() => _ConfiguredAppsScreenState();
}

class _ConfiguredAppsScreenState extends State<ConfiguredAppsScreen> {
  List<CustomAppModel> _allApps = [];
  List<CustomAppModel> _filteredApps = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    // 1. Fetch cached apps from SQLite database instantly
    final cachedApps = await AppDbHelper.instance.getAppsWithTracking();
    if (cachedApps.isNotEmpty && mounted) {
      setState(() {
        _allApps = cachedApps;
        _isLoading = false;
        _applySearch(_searchController.text);
      });
    } else if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    // 2. Sync system apps in background without blocking UI
    AppDbHelper.instance.syncAppsWithSystem().then((hasChanges) async {
      if (hasChanges || cachedApps.isEmpty) {
        final updatedApps = await AppDbHelper.instance.getAppsWithTracking();
        if (mounted) {
          setState(() {
            _allApps = updatedApps;
            _isLoading = false;
            _applySearch(_searchController.text);
          });
        }
      }
    });
  }

  void _applySearch(String query) {
    if (query.trim().isEmpty) {
      _filteredApps = List.from(_allApps);
    } else {
      _filteredApps = _allApps
          .where((app) =>
              app.displayName.toLowerCase().contains(query.trim().toLowerCase()) ||
              app.packageName.toLowerCase().contains(query.trim().toLowerCase()))
          .toList();
    }
  }

  bool get _isSelectAllChecked {
    if (_allApps.isEmpty) return false;
    return _allApps.every((app) => app.isTracking == 1);
  }

  Future<void> _toggleSelectAll(bool? value) async {
    final newStatus = value ?? false;
    final int statusInt = newStatus ? 1 : 0;

    setState(() {
      _allApps = _allApps.map((app) {
        return CustomAppModel(
          packageName: app.packageName,
          displayName: app.displayName,
          icon: app.icon,
          isSystemApp: app.isSystemApp,
          isFavorite: app.isFavorite,
          isTracking: statusInt,
          countdown: app.countdown,
          lastOpened: app.lastOpened,
          todayLimit: app.todayLimit,
          todayUsage: app.todayUsage,
          extraLimit: app.extraLimit,
          sessionLimit: app.sessionLimit,
          sessionUsage: app.sessionUsage,
        );
      }).toList();
      _applySearch(_searchController.text);
    });

    // Update SQLite DB in background without blocking UI or full reloading
    AppDbHelper.instance.updateAllTrackingStatus(newStatus);
  }

  Future<void> _toggleAppTracking(CustomAppModel app) async {
    final newStatus = app.isTracking != 1;
    final int newStatusInt = newStatus ? 1 : 0;

    setState(() {
      final index = _allApps.indexWhere((a) => a.packageName == app.packageName);
      if (index != -1) {
        final oldApp = _allApps[index];
        _allApps[index] = CustomAppModel(
          packageName: oldApp.packageName,
          displayName: oldApp.displayName,
          icon: oldApp.icon,
          isSystemApp: oldApp.isSystemApp,
          isFavorite: oldApp.isFavorite,
          isTracking: newStatusInt,
          countdown: oldApp.countdown,
          lastOpened: oldApp.lastOpened,
          todayLimit: oldApp.todayLimit,
          todayUsage: oldApp.todayUsage,
          extraLimit: oldApp.extraLimit,
          sessionLimit: oldApp.sessionLimit,
          sessionUsage: oldApp.sessionUsage,
        );
      }
      _applySearch(_searchController.text);
    });

    // Update SQLite DB in background without blocking UI or full reloading
    AppDbHelper.instance.updateTrackingStatus(app.packageName, newStatus);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Back Button & Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.black,
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Configured apps',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: Colors.black,
                    width: 1.2,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: Colors.black,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _applySearch(val);
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Search Apps',
                          hintStyle: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 16,
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
                          setState(() {
                            _applySearch('');
                          });
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
            const SizedBox(height: 12),

            // Apps List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Select All Option
                        _buildSelectAllTile(),
                        const SizedBox(height: 8),

                        // App Items List
                        ..._filteredApps.map((app) => _buildAppTile(app)),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectAllTile() {
    final isChecked = _isSelectAllChecked;
    return InkWell(
      onTap: () => _toggleSelectAll(!isChecked),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: const Icon(
                Icons.format_list_bulleted_rounded,
                color: Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Select all',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            _buildCustomCheckbox(isChecked: isChecked),
          ],
        ),
      ),
    );
  }

  Widget _buildAppTile(CustomAppModel app) {
    final isChecked = app.isTracking == 1;

    return InkWell(
      onTap: () => _toggleAppTracking(app),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
        child: Row(
          children: [
            // App Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12.0),
              ),
              clipBehavior: Clip.antiAlias,
              child: app.icon != null && app.icon!.isNotEmpty
                  ? Image.memory(
                      app.icon!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.android_rounded,
                        color: Colors.black87,
                      ),
                    )
                  : const Icon(
                      Icons.android_rounded,
                      color: Colors.black87,
                    ),
            ),
            const SizedBox(width: 14),

            // App Title
            Expanded(
              child: Text(
                app.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),

            // Checkbox
            _buildCustomCheckbox(isChecked: isChecked),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomCheckbox({required bool isChecked}) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isChecked ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: isChecked ? Colors.black : const Color(0xFF1E1E1E),
          width: 2.0,
        ),
      ),
      child: isChecked
          ? const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 16,
            )
          : null,
    );
  }
}
