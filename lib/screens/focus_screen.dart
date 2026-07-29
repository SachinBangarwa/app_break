import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
import 'package:testproject/screens/focus_active_session_screen.dart';
import 'package:testproject/screens/focus_apps_screen.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  List<String> _blockedPackages = [];
  AppInfo? _firstBlockedAppInfo;
  int _focusDurationMinutes = 30;

  @override
  void initState() {
    super.initState();
    _loadFocusSettings();
  }

  Future<void> _loadFocusSettings() async {
    final apps = await UsageDataSaver.getFocusBlockedApps();
    final duration = await UsageDataSaver.getFocusDuration();
    final startTime = await UsageDataSaver.getFocusSessionStart();

    AppInfo? firstApp;
    if (apps.isNotEmpty) {
      final allApps = await AppDbHelper.instance.getApps(excludeSystemApps: false);
      for (var a in allApps) {
        if (a.packageName == apps.first) {
          firstApp = a;
          break;
        }
      }
    }

    if (mounted) {
      setState(() {
        _blockedPackages = apps;
        _firstBlockedAppInfo = firstApp;
        _focusDurationMinutes = duration;
      });

      // Auto-restore active session if currently running
      if (startTime > 0) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final totalMs = duration * 60 * 1000;
        if ((nowMs - startTime) < totalMs) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FocusActiveSessionScreen(
                startTimeMs: startTime,
                durationMinutes: duration,
              ),
            ),
          );
        } else {
          await UsageDataSaver.clearFocusSessionStart();
        }
      }
    }
  }

  String _formatDurationLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    } else {
      final hours = minutes ~/ 60;
      final remMinutes = minutes % 60;
      if (remMinutes == 0) {
        return hours == 1 ? '1 hour' : '$hours hours';
      } else {
        return '$hours hr $remMinutes min';
      }
    }
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Focus Mode"),
        content: const Text(
          "During a Focus Session, access to configured apps is strictly blocked to help you stay focused on your work.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got it"),
          ),
        ],
      ),
    );
  }

  void _showFocusDurationBottomSheet(BuildContext context) {
    final List<Map<String, dynamic>> durationOptions = [
      {'label': '10 min', 'minutes': 10},
      {'label': '20 min', 'minutes': 20},
      {'label': '30 min', 'minutes': 30},
      {'label': '45 min', 'minutes': 45},
      {'label': '1 hour', 'minutes': 60},
      {'label': '90 min', 'minutes': 90},
      {'label': '2 hours', 'minutes': 120},
      {'label': '3 hours', 'minutes': 180},
      {'label': '4 hours', 'minutes': 240},
      {'label': '5 hours', 'minutes': 300},
      {'label': '6 hours', 'minutes': 360},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: SafeArea(
                child: Column(
                  children: [
                    // Header Bar with Title & Close Icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Focus duration',
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

                    // Duration Radio Options List
                    Expanded(
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: durationOptions.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFF3F4F6),
                        ),
                        itemBuilder: (context, index) {
                          final item = durationOptions[index];
                          final String label = item['label'] as String;
                          final int minutes = item['minutes'] as int;
                          final bool isSelected = _focusDurationMinutes == minutes;

                          return InkWell(
                            onTap: () async {
                              setState(() {
                                _focusDurationMinutes = minutes;
                              });
                              setModalState(() {});
                              await UsageDataSaver.saveFocusDuration(minutes);
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                  _buildCustomRadioButton(isSelected: isSelected),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
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

  Widget _buildCustomRadioButton({required bool isSelected}) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.black,
          width: 2.0,
        ),
      ),
      padding: const EdgeInsets.all(3.0),
      child: isSelected
          ? Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Info Icon Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: () => _showInfoDialog(context),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            color: Colors.black,
                            size: 24,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),

                    // Main Title
                    const Text(
                      'Focus',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Description
                    const Text(
                      'During Focus Session, you won\'t be able to access apps configured with Ascent — not even through Pause Screen. This helps to concentrate on a particular task without any distraction',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Section 1: Blocked apps
                    const Text(
                      'Blocked apps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Dynamic Blocked Apps Card Tile
                    _buildBlockedAppsCardTile(context),
                    const SizedBox(height: 28),

                    // Section 2: Setup
                    const Text(
                      'Setup',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildCardTile(
                      icon: Icons.timer_outlined,
                      title: 'Set Focus duration',
                      onTap: () => _showFocusDurationBottomSheet(context),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom Action Button: Start Focus Session (30 min)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final startTime = DateTime.now().millisecondsSinceEpoch;
                    await UsageDataSaver.saveFocusSessionStart(startTime);
                    if (context.mounted) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FocusActiveSessionScreen(
                            startTimeMs: startTime,
                            durationMinutes: _focusDurationMinutes,
                          ),
                        ),
                      );
                      _loadFocusSettings();
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
                  child: Text(
                    'Start Focus Session (${_formatDurationLabel(_focusDurationMinutes)})',
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

  Widget _buildBlockedAppsCardTile(BuildContext context) {
    final int count = _blockedPackages.length;
    String displayTitle = 'Add apps';
    Widget iconWidget = const Icon(Icons.add_rounded, color: Colors.black87, size: 22);

    if (count == 1) {
      displayTitle = _firstBlockedAppInfo?.name ?? '1 app selected';
      if (_firstBlockedAppInfo?.icon != null && _firstBlockedAppInfo!.icon!.isNotEmpty) {
        iconWidget = ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: Image.memory(
            _firstBlockedAppInfo!.icon!,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
          ),
        );
      } else {
        iconWidget = const Icon(Icons.android_rounded, color: Colors.black87, size: 22);
      }
    } else if (count > 1) {
      final int remaining = count - 1;
      final String appWord = remaining == 1 ? 'app' : 'apps';
      final String firstName = _firstBlockedAppInfo?.name ?? 'App';
      displayTitle = '$firstName and $remaining more $appWord';

      if (_firstBlockedAppInfo?.icon != null && _firstBlockedAppInfo!.icon!.isNotEmpty) {
        iconWidget = ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: Image.memory(
            _firstBlockedAppInfo!.icon!,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
          ),
        );
      } else {
        iconWidget = const Icon(Icons.android_rounded, color: Colors.black87, size: 22);
      }
    }

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const FocusAppsScreen(),
          ),
        );
        _loadFocusSettings();
      },
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12.0),
              ),
              alignment: Alignment.center,
              child: iconWidget,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                displayTitle,
                style: const TextStyle(
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

  Widget _buildCardTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1.0,
          ),
        ),
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
              child: Text(
                title,
                style: const TextStyle(
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
}
