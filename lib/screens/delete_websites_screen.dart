import 'package:flutter/material.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';

class DeleteWebsitesScreen extends StatefulWidget {
  const DeleteWebsitesScreen({super.key});

  @override
  State<DeleteWebsitesScreen> createState() => _DeleteWebsitesScreenState();
}

class _DeleteWebsitesScreenState extends State<DeleteWebsitesScreen> {
  List<Map<String, dynamic>> _websites = [];
  final Set<int> _selectedIdsToDelete = {};
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

  bool get _isDeleteAllChecked {
    if (_websites.isEmpty) return false;
    return _selectedIdsToDelete.length == _websites.length;
  }

  void _toggleDeleteAll(bool? value) {
    setState(() {
      if (value == true) {
        _selectedIdsToDelete.clear();
        for (var site in _websites) {
          _selectedIdsToDelete.add(site['id'] as int);
        }
      } else {
        _selectedIdsToDelete.clear();
      }
    });
  }

  void _toggleSiteSelection(int id) {
    setState(() {
      if (_selectedIdsToDelete.contains(id)) {
        _selectedIdsToDelete.remove(id);
      } else {
        _selectedIdsToDelete.add(id);
      }
    });
  }

  void _showConfirmationBottomSheet() {
    final deleteCount = _selectedIdsToDelete.length;
    if (deleteCount == 0) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bar: Title & Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Are you sure?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
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
                const SizedBox(height: 12),

                // Description Text
                const Text(
                  "Deletion can't be undone",
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 28),

                // Cancel & Delete Buttons Side-by-Side
                Row(
                  children: [
                    // Cancel Button
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: const BorderSide(
                              color: Colors.black,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Delete Button
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            final idsToDelete = _selectedIdsToDelete.toList();
                            await AppDbHelper.instance.deleteWebsites(idsToDelete);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final deleteCount = _selectedIdsToDelete.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Close Button & Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.black,
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Delete websites',
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

            // Header Description
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
              child: Text(
                "You can select which websites to delete. After deleting, you won't see them in the Websites list.",
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Websites List with Checkboxes
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Delete All Option
                        _buildDeleteAllTile(),
                        const SizedBox(height: 8),

                        // Site Items List
                        ..._websites.map((site) => _buildSiteTile(site)),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),

            // Bottom Action Button: Delete(N)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: deleteCount > 0 ? _showConfirmationBottomSheet : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: deleteCount > 0 ? Colors.black : const Color(0xFFE5E7EB),
                    foregroundColor: deleteCount > 0 ? Colors.white : const Color(0xFF9CA3AF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Delete($deleteCount)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteAllTile() {
    final isChecked = _isDeleteAllChecked;
    return InkWell(
      onTap: () => _toggleDeleteAll(!isChecked),
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
                Icons.delete_outline_rounded,
                color: Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Delete all',
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

  Widget _buildSiteTile(Map<String, dynamic> site) {
    final int id = site['id'] as int;
    final String domain = site['domain'] as String? ?? '';
    final isChecked = _selectedIdsToDelete.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: InkWell(
        onTap: () => _toggleSiteSelection(id),
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
