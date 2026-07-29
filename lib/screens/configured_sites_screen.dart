import 'package:flutter/material.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/screens/add_website_screen.dart';
import 'package:testproject/screens/delete_websites_screen.dart';

class ConfiguredSitesScreen extends StatefulWidget {
  const ConfiguredSitesScreen({super.key});

  @override
  State<ConfiguredSitesScreen> createState() => _ConfiguredSitesScreenState();
}

class _ConfiguredSitesScreenState extends State<ConfiguredSitesScreen> {
  List<Map<String, dynamic>> _websites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWebsites();
  }

  Future<void> _loadWebsites() async {
    final sites = await AppDbHelper.instance.getWebsites();
    if (mounted) {
      setState(() {
        _websites = List.from(sites);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleWebsiteSelection(Map<String, dynamic> site) async {
    final int id = site['id'] as int;
    final int currentStatus = site['isSelected'] as int? ?? 0;
    final bool newStatus = currentStatus != 1;
    final int newStatusInt = newStatus ? 1 : 0;

    // Instant UI update in memory - KEEP ITEM POSITION UNCHANGED while toggling!
    setState(() {
      final index = _websites.indexWhere((s) => s['id'] == id);
      if (index != -1) {
        final updatedSite = Map<String, dynamic>.from(_websites[index]);
        updatedSite['isSelected'] = newStatusInt;
        _websites[index] = updatedSite;
      }
    });

    // Update SQLite in background
    AppDbHelper.instance.updateWebsiteSelection(id, newStatus);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Back Button, Title, Pencil Edit Button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
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
                  const Expanded(
                    child: Text(
                      'Configured sites',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeleteWebsitesScreen(),
                        ),
                      );
                      _loadWebsites();
                    },
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: Colors.black,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Header Description Text
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
              child: Text(
                'Configure websites to use with Pause Exercise, App Limits, Reminders, Intentions and other features to help you stop mindless scrolling.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Main Content: Websites List
            Expanded(
              child:
                  _isLoading
                      ? const Center(
                        child: CircularProgressIndicator(color: Colors.black),
                      )
                      : _websites.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text(
                            'No websites configured yet.\nTap "Add website" below to add a website.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      )
                      : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          ..._websites.map((site) => _buildSiteTile(site)),
                          const SizedBox(height: 16),
                        ],
                      ),
            ),
          ],
        ),
      ),

      // Bottom Section: Add website with Top Divider
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFFF7F8FA),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(
                height: 0.5,
                thickness: 1,
                color: Color(0xFFE5E7EB),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: _buildAddWebsiteCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSiteTile(Map<String, dynamic> site) {
    final String domain = site['domain'] as String? ?? '';
    final bool isChecked = (site['isSelected'] as int? ?? 0) == 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: InkWell(
        onTap: () => _toggleWebsiteSelection(site),
        borderRadius: BorderRadius.circular(14.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Row(
            children: [
              // Icon Container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Domain Name
              Expanded(
                child: Text(
                  domain,
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
      ),
    );
  }

  Widget _buildAddWebsiteCard() {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddWebsiteScreen()),
        );
        _loadWebsites();
      },
      borderRadius: BorderRadius.circular(16.0),
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
                Icons.language_rounded,
                color: Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Add website',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
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
      child:
          isChecked
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
              : null,
    );
  }
}
