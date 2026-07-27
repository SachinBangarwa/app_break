import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:testproject/device_app/localSaver/active_apps_manager.dart';

class OverlayWindow extends StatefulWidget {
  final String initialOverlayType;
  final String initialPackageName;
  final String initialAppName;
  final int initialLimitMinutes;
  final int initialLimitMs;
  final int initialTodayUsageMs;
  final int initialSessionLimitMs;
  final int initialSessionUsageMs;

  const OverlayWindow({
    super.key,
    this.initialOverlayType = "session_prompt",
    this.initialPackageName = "",
    this.initialAppName = "This application",
    this.initialLimitMinutes = 0,
    this.initialLimitMs = 0,
    this.initialTodayUsageMs = 0,
    this.initialSessionLimitMs = 0,
    this.initialSessionUsageMs = 0,
  });

  @override
  State<OverlayWindow> createState() => _OverlayWindowState();
}

class _OverlayWindowState extends State<OverlayWindow> {
  String _overlayType = "session_prompt";
  String _appName = "This application";
  String _packageName = "";
  int _todayUsageMs = 0;
  int _sessionLimitMs = 0;
  int _sessionUsageMs = 0;
  bool _showBottomSheet = false;

  final List<Map<String, dynamic>> _sessionOptions = const [
    {'label': '1 min', 'minutes': 1},
    {'label': '3 min', 'minutes': 3},
    {'label': '5 min', 'minutes': 5},
    {'label': '10 min', 'minutes': 10},
    {'label': '15 min', 'minutes': 15},
    {'label': '20 min', 'minutes': 20},
    {'label': '30 min', 'minutes': 30},
    {'label': '45 min', 'minutes': 45},
    {'label': '1 hour', 'minutes': 60},
    {'label': '90 min', 'minutes': 90},
  ];

  @override
  void initState() {
    super.initState();
    _overlayType = widget.initialOverlayType;
    _packageName = widget.initialPackageName;
    _appName = widget.initialAppName;
    _todayUsageMs = widget.initialTodayUsageMs;
    _sessionLimitMs = widget.initialSessionLimitMs;
    _sessionUsageMs = widget.initialSessionUsageMs;
  }

  @override
  void didUpdateWidget(covariant OverlayWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialOverlayType != oldWidget.initialOverlayType ||
        widget.initialPackageName != oldWidget.initialPackageName ||
        widget.initialAppName != oldWidget.initialAppName ||
        widget.initialTodayUsageMs != oldWidget.initialTodayUsageMs ||
        widget.initialSessionLimitMs != oldWidget.initialSessionLimitMs ||
        widget.initialSessionUsageMs != oldWidget.initialSessionUsageMs) {
      setState(() {
        _overlayType = widget.initialOverlayType;
        _packageName = widget.initialPackageName;
        _appName = widget.initialAppName;
        _todayUsageMs = widget.initialTodayUsageMs;
        _sessionLimitMs = widget.initialSessionLimitMs;
        _sessionUsageMs = widget.initialSessionUsageMs;
        _showBottomSheet = false;
      });
    }
  }

  Future<void> _closeAppAndGoHome() async {
    if (_packageName.isNotEmpty) {
      try {
        try {
          final service = FlutterBackgroundService();
          service.invoke('limitChanged', {
            'packageName': _packageName,
          });
        } catch (e) {
        }
        await InstalledApps.startApp("com.example.testproject");
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
      }
    }
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _selectSessionLimit(int minutes) async {
    if (_packageName.isEmpty) {
      await FlutterOverlayWindow.closeOverlay();
      return;
    }

    try {
      final service = FlutterBackgroundService();
      service.invoke('setSessionLimit', {
        'packageName': _packageName,
        'sessionMinutes': minutes,
      });

      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
    } finally {
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spentMinutes = (_todayUsageMs / 60000).floor();
    final sessionLimitMin = (_sessionLimitMs / 60000).round();
    final sessionUsageMin = (_sessionUsageMs / 60000).floor();
    final topPadding = MediaQuery.of(context).padding.top;
    final isBlockMode = _overlayType == 'block';

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Main Screen Layout
          SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.white,
              padding: EdgeInsets.only(
                left: 28,
                right: 28,
                top: topPadding > 60 ? topPadding + 48 : 80,
                bottom: 24,
              ),
              child: Column(
                children: [
                  // Top Subtitle: "YouTube is paused by App Break"
                  Text(
                    '$_appName is paused by App Break',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.black87,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 2),

                  // Center Icon (Hourglass for block, Heart for session prompt)
                  Icon(
                    isBlockMode
                        ? Icons.hourglass_bottom_rounded
                        : Icons.favorite_border_rounded,
                    size: 84,
                    color: isBlockMode
                        ? Colors.red.shade600
                        : Colors.black.withValues(alpha: 0.85),
                  ),

                  const SizedBox(height: 32),

                  // Main Headline
                  Text(
                    isBlockMode
                        ? 'Time Limit Reached'
                        : 'Do you really need it\nnow?',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 1.25,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Subtext
                  Text(
                    isBlockMode
                        ? 'You have used $_appName for $spentMinutes m today.\nPlease take a break!'
                        : sessionLimitMin > 0
                            ? 'Time spent: $sessionUsageMin m / $sessionLimitMin m'
                            : 'Time spent: $spentMinutes m',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 3),

                  // Primary Button: "Close app"
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _closeAppAndGoHome,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Close app',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Secondary Button: "Continue in app" (ONLY for session_prompt)
                  if (!isBlockMode)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: () {
                          final opt = ActiveAppsManager.reminderOptionSetting;
                          if (opt == -1) {
                            _selectSessionLimit(-1);
                          } else if (opt > 0) {
                            _selectSessionLimit(opt);
                          } else {
                            setState(() {
                              _showBottomSheet = true;
                            });
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                        ),
                        child: const Text(
                          'Continue in app',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Bottom Sheet Modal Overlay (Matching User's Screenshot)
          if (_showBottomSheet)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.4),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.78,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Bottom Sheet Header: Title & Close Button
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'How long do you need it?',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.black87,
                                  size: 24,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showBottomSheet = false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 1, thickness: 1),

                        // Time Options List
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _sessionOptions.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, thickness: 0.5),
                            itemBuilder: (context, index) {
                              final item = _sessionOptions[index];
                              final label = item['label'] as String;
                              final minutes = item['minutes'] as int;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 4,
                                ),
                                title: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.black87,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.black54,
                                  size: 22,
                                ),
                                onTap: () => _selectSessionLimit(minutes),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
