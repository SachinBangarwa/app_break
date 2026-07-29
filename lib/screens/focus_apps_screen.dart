import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';

class FocusAppsScreen extends StatefulWidget {
  const FocusAppsScreen({super.key});

  @override
  State<FocusAppsScreen> createState() => _FocusAppsScreenState();
}

class _FocusAppsScreenState extends State<FocusAppsScreen> {
  List<AppInfo> _allApps = [];
  Set<String> _selectedPackages = {};
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFocusApps();
  }

  Future<void> _loadFocusApps() async {
    final savedFocusList = await UsageDataSaver.getFocusBlockedApps();
    final apps = await AppDbHelper.instance.getApps(excludeSystemApps: true);

    final set = Set<String>.from(savedFocusList);

    // Sort apps on initial load: selected apps first, then alphabetically by name
    apps.sort((a, b) {
      final bool aSel = set.contains(a.packageName);
      final bool bSel = set.contains(b.packageName);
      if (aSel != bSel) return bSel ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    if (mounted) {
      setState(() {
        _allApps = apps;
        _selectedPackages = set;
        _isLoading = false;
      });
    }
  }

  void _toggleAppSelection(String packageName) {
    setState(() {
      if (_selectedPackages.contains(packageName)) {
        _selectedPackages.remove(packageName);
      } else {
        _selectedPackages.add(packageName);
      }
    });

    // Save updated list to SharedPreferences
    UsageDataSaver.saveFocusBlockedApps(_selectedPackages.toList());
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      if (value == true || _selectedPackages.length < _allApps.length) {
        _selectedPackages = _allApps.map((a) => a.packageName).toSet();
      } else {
        _selectedPackages.clear();
      }
    });
    UsageDataSaver.saveFocusBlockedApps(_selectedPackages.toList());
  }

  List<AppInfo> get _filteredApps {
    if (_searchQuery.trim().isEmpty) return _allApps;
    final q = _searchQuery.trim().toLowerCase();
    return _allApps
        .where((a) =>
            a.name.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
  }

  bool get _isSelectAllChecked {
    if (_allApps.isEmpty) return false;
    return _selectedPackages.length == _allApps.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Back Arrow & Title
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
                    'Blocked apps',
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

            // Search Bar matching screenshot
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
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
                      color: Colors.black87,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        style: const TextStyle(fontSize: 16, color: Colors.black),
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
                            _searchQuery = '';
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
            const SizedBox(height: 16),

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
                        // Select All Tile
                        _buildSelectAllTile(),
                        const SizedBox(height: 8),

                        // Apps List Tiles
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
      borderRadius: BorderRadius.circular(14.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
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

  Widget _buildAppTile(AppInfo app) {
    final bool isChecked = _selectedPackages.contains(app.packageName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: InkWell(
        onTap: () => _toggleAppSelection(app.packageName),
        borderRadius: BorderRadius.circular(14.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
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

              // App Name
              Expanded(
                child: Text(
                  app.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),

              // Custom Checkbox
              _buildCustomCheckbox(isChecked: isChecked),
            ],
          ),
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
