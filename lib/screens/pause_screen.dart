import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
import 'package:testproject/screens/app_limits_screen.dart';
import 'package:testproject/screens/configured_apps_screen.dart';
import 'package:testproject/screens/reminder_screen.dart';

class PauseScreen extends StatefulWidget {
  const PauseScreen({super.key});

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  bool isPauseProtectionActive = true;
  int selectedBottomNavIndex = 1; // "Pause" is selected by default
  int _selectedAppsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSelectedAppsCount();
  }

  Future<void> _loadSelectedAppsCount() async {
    final count = await AppDbHelper.instance.getTrackingCount();
    if (mounted) {
      setState(() {
        _selectedAppsCount = count;
      });
    }
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Pause',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Take control, Pause distractions.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF555555),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.black,
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Pause Protection Card
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18.0),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Pause Circle Badge Icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF3F4F6),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 2.0,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.pause_rounded,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Title, Subtitle, Active Badge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pause Protection',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pause distraction apps\nand stay focused.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF888888),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Active Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // iOS Style Switch
                    CupertinoSwitch(
                      value: isPauseProtectionActive,
                      activeTrackColor: Colors.black,
                      onChanged: (val) {
                        setState(() {
                          isPauseProtectionActive = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // WHAT TO PROTECT Section
              const Text(
                'WHAT TO PROTECT',
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
                    _buildOptionItem(
                      icon: Icons.grid_view_rounded,
                      title: 'Apps',
                      subtitle: '$_selectedAppsCount apps selected',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ConfiguredAppsScreen(),
                          ),
                        );
                        _loadSelectedAppsCount();
                      },
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF3F4F6),
                      indent: 64,
                    ),
                    _buildOptionItem(
                      icon: Icons.language_rounded,
                      title: 'Websites',
                      subtitle: '1 sites selected',
                      onTap: () {},
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF3F4F6),
                      indent: 64,
                    ),
                    _buildOptionItem(
                      icon: Icons.link_rounded,
                      title: 'Shortcuts',
                      subtitle: '0 shortcuts',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // EXPERIENCE Section
              const Text(
                'EXPERIENCE',
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
                    _buildOptionItem(
                      icon: Icons.phonelink_setup_rounded,
                      title: 'Customize Pause Screen',
                      subtitle: 'Choose what appears when you pause',
                      onTap: () => _showPauseDurationModal(context),
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF3F4F6),
                      indent: 64,
                    ),
                    _buildOptionItem(
                      icon: Icons.hourglass_bottom_rounded,
                      title: 'Set up Limits',
                      subtitle: 'Limit time spent on selected apps',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppLimitsScreen(),
                          ),
                        );
                        _loadSelectedAppsCount();
                      },
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF3F4F6),
                      indent: 64,
                    ),
                    _buildOptionItem(
                      icon: Icons.grid_view_rounded,
                      title: 'Set Intentions',
                      subtitle: "Remind yourself why you're pausing",
                      onTap: () {},
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF3F4F6),
                      indent: 64,
                    ),
                    _buildOptionItem(
                      icon: Icons.notifications_none_rounded,
                      title: 'Set up Reminder',
                      subtitle: 'Get reminded to take breaks',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReminderScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),

      // Bottom Navigation Bar
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE5E7EB), width: 1.0),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.access_time_rounded,
                label: 'Overview',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.pause_circle_filled_rounded,
                label: 'Pause',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.shield_outlined,
                label: 'Blocking',
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.history_rounded,
                label: 'Portal',
              ),
              _buildNavItem(
                index: 4,
                icon: Icons.track_changes_rounded,
                label: 'Focus',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPauseDurationModal(BuildContext context) async {
    int currentDuration = await UsageDataSaver.getDefaultPauseDuration();

    final durations = [
      {'label': '2 seconds', 'val': 2},
      {'label': '4 seconds', 'val': 4},
      {'label': '6 seconds', 'val': 6},
      {'label': '10 seconds', 'val': 10},
      {'label': '15 seconds', 'val': 15},
      {'label': '20 seconds', 'val': 20},
      {'label': '40 seconds', 'val': 40},
      {'label': '1 minute', 'val': 60},
    ];

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Title & Close Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Pause duration',
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
                    const SizedBox(height: 12),

                    // Options List
                    Column(
                      children: durations.map((item) {
                        final label = item['label'] as String;
                        final val = item['val'] as int;
                        final isSelected = currentDuration == val;

                        return InkWell(
                          onTap: () async {
                            setModalState(() {
                              currentDuration = val;
                            });
                            await UsageDataSaver.saveDefaultPauseDuration(val);
                            await AppDbHelper.instance.updateAllAppCountdown(val);
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 4.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.black : const Color(0xFF9CA3AF),
                                      width: isSelected ? 6.5 : 1.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            // Icon Badge
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Icon(icon, color: Colors.black87, size: 20),
            ),
            const SizedBox(width: 14),

            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
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

            // Chevron Arrow
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

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool isSelected = selectedBottomNavIndex == index;
    final Color itemColor = isSelected ? Colors.black : const Color(0xFF6F6F6F);

    return InkWell(
      onTap: () {
        setState(() {
          selectedBottomNavIndex = index;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: itemColor, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: itemColor,
            ),
          ),
        ],
      ),
    );
  }
}
