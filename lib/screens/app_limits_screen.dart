import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:testproject/device_app/localSaver/custom_app_model.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';

class AppLimitsScreen extends StatefulWidget {
  const AppLimitsScreen({super.key});

  @override
  State<AppLimitsScreen> createState() => _AppLimitsScreenState();
}

class _AppLimitsScreenState extends State<AppLimitsScreen> {
  List<CustomAppModel> _trackedApps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrackedApps();
  }

  Future<void> _loadTrackedApps({bool showLoading = false}) async {
    if (showLoading && _trackedApps.isEmpty && mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    final apps = await AppDbHelper.instance.getTrackingApps();
    if (mounted) {
      setState(() {
        _trackedApps = apps;
        _isLoading = false;
      });
    }
  }

  String _formatLimit(int limitMs) {
    if (limitMs <= 0) return 'Unlimited';
    final totalMinutes = (limitMs / 60000).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '$hours h $minutes m';
    } else if (hours > 0) {
      return '$hours h';
    } else {
      return '$minutes m';
    }
  }

  void _showSetDurationModal(CustomAppModel app) {
    int initialMinutes = app.todayLimit > 0 ? (app.todayLimit / 60000).round() : 0;
    int selectedHours = initialMinutes ~/ 60;
    int selectedMinutes = initialMinutes % 60;

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
                    // Handle Bar
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Top Bar: Title & Close Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Set Duration',
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
                    const SizedBox(height: 20),

                    // Column Headers (Hours & Minutes)
                    Row(
                      children: const [
                        Expanded(
                          child: Center(
                            child: Text(
                              'Hours',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'Minutes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Cupertino Pickers for Hours & Minutes
                    SizedBox(
                      height: 180,
                      child: Row(
                        children: [
                          // Hours Wheel (0 - 23)
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              scrollController: FixedExtentScrollController(
                                initialItem: selectedHours,
                              ),
                              onSelectedItemChanged: (index) {
                                setModalState(() {
                                  selectedHours = index;
                                });
                              },
                              children: List.generate(24, (index) {
                                return Center(
                                  child: Text(
                                    '$index',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),

                          // Minutes Wheel (0 - 59)
                          Expanded(
                            child: CupertinoPicker(
                              itemExtent: 40,
                              scrollController: FixedExtentScrollController(
                                initialItem: selectedMinutes,
                              ),
                              onSelectedItemChanged: (index) {
                                setModalState(() {
                                  selectedMinutes = index;
                                });
                              },
                              children: List.generate(60, (index) {
                                return Center(
                                  child: Text(
                                    '$index',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          final totalMin = (selectedHours * 60) + selectedMinutes;
                          final newLimitMs = totalMin * 60 * 1000;
                          await AppDbHelper.instance.updateAppLimit(
                            app.packageName,
                            newLimitMs,
                            app.todayUsage,
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                          await _loadTrackedApps();
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
                          'Save',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: Back Button, Title, Info Icon
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
                  const Expanded(
                    child: Text(
                      'App Limits',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
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
            ),

            // Header Subtitle Text
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
              child: Text(
                'Select an app and set a daily usage limit. Once the limit is reached, the app will be restricted for the rest of the day.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tracked Apps List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : _trackedApps.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              'No apps configured for protection.\nSelect apps in "Apps" menu first.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          physics: const BouncingScrollPhysics(),
                          itemCount: _trackedApps.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final app = _trackedApps[index];
                            final formattedLimit = _formatLimit(app.todayLimit);

                            return InkWell(
                              onTap: () => _showSetDurationModal(app),
                              borderRadius: BorderRadius.circular(16.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 14.0,
                                ),
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
                                        app.displayName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),

                                    // Limit Display Text
                                    Text(
                                      formattedLimit,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: app.todayLimit > 0
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: app.todayLimit > 0
                                            ? Colors.black87
                                            : const Color(0xFF9CA3AF),
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    // Chevron Right
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFF9CA3AF),
                                      size: 22,
                                    ),
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
  }
}
