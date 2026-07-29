import 'dart:async';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
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
  bool _isSessionActive = false;
  int _remainingSeconds = 0;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _loadFocusSettings();
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFocusSettings() async {
    final apps = await UsageDataSaver.getFocusBlockedApps();
    final duration = await UsageDataSaver.getFocusDuration();
    final startTime = await UsageDataSaver.getFocusSessionStart();

    AppInfo? firstApp;
    if (apps.isNotEmpty) {
      final allApps = await AppDbHelper.instance.getApps(
        excludeSystemApps: false,
      );
      for (var a in allApps) {
        if (a.packageName == apps.first) {
          firstApp = a;
          break;
        }
      }
    }

    bool active = false;
    int remSecs = 0;
    if (startTime > 0) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final totalMs = duration * 60 * 1000;
      final elapsed = nowMs - startTime;
      if (elapsed < totalMs) {
        active = true;
        remSecs = ((totalMs - elapsed) / 1000).ceil();
      } else {
        await UsageDataSaver.clearFocusSessionStart();
      }
    }

    if (mounted) {
      setState(() {
        _blockedPackages = apps;
        _firstBlockedAppInfo = firstApp;
        _focusDurationMinutes = duration;
        _isSessionActive = active;
        _remainingSeconds = remSecs;
      });

      if (active) {
        _startTickerTimer();
      } else {
        _tickerTimer?.cancel();
      }
    }
  }

  void _startTickerTimer() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final startTime = await UsageDataSaver.getFocusSessionStart();
      final duration = await UsageDataSaver.getFocusDuration();
      if (startTime <= 0) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isSessionActive = false;
            _remainingSeconds = 0;
          });
        }
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final totalMs = duration * 60 * 1000;
      final elapsed = nowMs - startTime;
      final remMs = totalMs - elapsed;

      if (remMs <= 0) {
        timer.cancel();
        await UsageDataSaver.clearFocusSessionStart();
        if (mounted) {
          setState(() {
            _isSessionActive = false;
            _remainingSeconds = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _remainingSeconds = (remMs / 1000).ceil();
          });
        }
      }
    });
  }

  String _formatTimerText(int seconds) {
    if (seconds <= 0) return '00:00';
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;

    final String minStr = minutes.toString().padLeft(2, '0');
    final String secStr = secs.toString().padLeft(2, '0');

    if (hours > 0) {
      final String hrStr = hours.toString().padLeft(2, '0');
      return '$hrStr:$minStr:$secStr';
    } else {
      return '$minStr:$secStr';
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
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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

  Widget _buildActiveSessionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.0),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: const [
              Icon(Icons.shield_outlined, size: 72, color: Colors.black),
              Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Icon(Icons.favorite_rounded, size: 24, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Stay focused',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatTimerText(_remainingSeconds),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedAppsCardTile(BuildContext context) {
    String titleText = 'Add apps';
    Widget leadWidget = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.apps_rounded,
        color: Color(0xFF4B5563),
        size: 24,
      ),
    );

    if (_blockedPackages.isNotEmpty) {
      if (_firstBlockedAppInfo != null && _firstBlockedAppInfo?.icon != null) {
        leadWidget = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            _firstBlockedAppInfo!.icon!,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        );
      }
      final firstName = _firstBlockedAppInfo?.name ?? 'App';
      final total = _blockedPackages.length;
      if (total == 1) {
        titleText = firstName;
      } else {
        final remaining = total - 1;
        titleText = '$firstName and $remaining more app${remaining > 1 ? 's' : ''}';
      }
    }

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FocusAppsScreen()),
        );
        _loadFocusSettings();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.0),
        ),
        child: Row(
          children: [
            leadWidget,
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                titleText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 24,
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
    String subText = _formatDurationLabel(_focusDurationMinutes);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF4B5563), size: 24),
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
            Text(
              subText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _showFocusDurationBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final options = [
              10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 360,
            ];

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Set Focus Duration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (context, index) => const Divider(
                        height: 1,
                        color: Color(0xFFF3F4F6),
                      ),
                      itemBuilder: (context, index) {
                        final minutes = options[index];
                        final isSelected = minutes == _focusDurationMinutes;
                        final label = _formatDurationLabel(minutes);

                        return InkWell(
                          onTap: () async {
                            setState(() {
                              _focusDurationMinutes = minutes;
                            });
                            setModalState(() {});
                            await UsageDataSaver.saveFocusDuration(minutes);
                            await UsageDataSaver.clearFocusSessionStart();
                            _loadFocusSettings();
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
          color: isSelected ? Colors.black : const Color(0xFFD1D5DB),
          width: isSelected ? 6.5 : 1.5,
        ),
      ),
    );
  }

  void _showStopFocusConfirmationBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        int countdown = 5;
        double progress = 0.0;
        Timer? delayTimer;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            delayTimer ??= Timer.periodic(const Duration(milliseconds: 100), (timer) {
              final newProgress = (timer.tick * 100) / 5000.0;
              final newCountdown = 5 - (timer.tick / 10).floor();

              if (newProgress >= 1.0) {
                timer.cancel();
                if (ctx.mounted) {
                  setSheetState(() {
                    progress = 1.0;
                    countdown = 0;
                  });
                }
              } else {
                if (ctx.mounted) {
                  setSheetState(() {
                    progress = newProgress;
                    countdown = newCountdown.clamp(0, 5);
                  });
                }
              }
            });

            final bool isEnabled = countdown <= 0;

            return Container(
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: const Color(0xFFECECEC),
                borderRadius: BorderRadius.circular(24.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Stop the Focus Session?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          delayTimer?.cancel();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  const Text(
                    'If you do, you won\'t be able to return to this session',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4B5563),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: InkWell(
                            onTap: isEnabled
                                ? () async {
                                    delayTimer?.cancel();
                                    await UsageDataSaver.clearFocusSessionStart();
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                    _loadFocusSettings();
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(16.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isEnabled
                                      ? Colors.transparent
                                      : const Color(0xFFC4C4C4),
                                  borderRadius: BorderRadius.circular(16.0),
                                ),
                                child: Stack(
                                  children: [
                                    if (!isEnabled)
                                      FractionallySizedBox(
                                        widthFactor: progress.clamp(0.0, 1.0),
                                        heightFactor: 1.0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16.0),
                                          ),
                                        ),
                                      ),

                                    Center(
                                      child: isEnabled
                                          ? const Text(
                                              'Stop',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                            )
                                          : Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Text(
                                                  'Stop',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                Text(
                                                  '$countdown',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),

                                    IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16.0),
                                          border: Border.all(
                                            color: isEnabled
                                                ? Colors.black
                                                : const Color(0xFF9E9E9E),
                                            width: 1.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              delayTimer?.cancel();
                              Navigator.pop(ctx);
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
                              'Resume',
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
                ],
              ),
            );
          },
        );
      },
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
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
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

                    const Text(
                      'During Focus Session, you won\'t be able to access apps configured with Ascent — not even through Pause Screen. This helps to concentrate on a particular task without any distraction',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    if (_isSessionActive)
                      _buildActiveSessionCard()
                    else ...[
                      const Text(
                        'Blocked apps',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _buildBlockedAppsCardTile(context),
                      const SizedBox(height: 28),

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
                  ],
                ),
              ),
            ),

            // Bottom Action Button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 16.0,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_isSessionActive) {
                      _showStopFocusConfirmationBottomSheet(context);
                    } else {
                      final startTime = DateTime.now().millisecondsSinceEpoch;
                      await UsageDataSaver.saveFocusSessionStart(startTime);
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
                    _isSessionActive
                        ? 'Stop Focus Session'
                        : 'Start Focus Session (${_formatDurationLabel(_focusDurationMinutes)})',
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
}
