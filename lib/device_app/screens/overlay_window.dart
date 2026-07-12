
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:installed_apps/installed_apps.dart';
import '../localSaver/localSaver.dart';
class OverlayWindow extends StatefulWidget {
  const OverlayWindow({super.key});

  @override
  State<OverlayWindow> createState() => _OverlayWindowState();
}
class _OverlayWindowState extends State<OverlayWindow> {
  String _appName = "This application";
  String _packageName = "";
  int _currentLimitMinutes = 0;
  bool _isExtending = false; // इसे अब नीचे रीसेट किया जाएगा
  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _loadOverlayData();

    // जब भी बैकग्राउंड सर्विस से नया ब्लॉक डेटा आएगा, हम लोडर को रीसेट कर देंगे
    _dataSubscription = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map) {
        final pkg = event['packageName'] as String?;
        final name = event['appName'] as String?;
        final limitMin = event['limitMinutes'] as int?;
        if (pkg != null && pkg.isNotEmpty) {
          setState(() {
            _packageName = pkg;
            _appName = name ?? pkg;
            if (limitMin != null) _currentLimitMinutes = limitMin;
            _isExtending = false; // FIX 1: नया पॉपअप आने पर लोडर बंद करें
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadOverlayData() async {
    await UsageDataSaver.reload();
    final activePackage = await UsageDataSaver.getActiveBlockedPackage() ?? '';
    final activeName = await UsageDataSaver.getActiveBlockedName() ?? 'This application';
    final limitMs = await UsageDataSaver.getLimit(activePackage);

    setState(() {
      _packageName = activePackage;
      _appName = activeName;
      _currentLimitMinutes = (limitMs / 60000).round();
      _isExtending = false; // Safe fallback reset
    });
  }

  Future<void> _extendLimit() async {
    if (_packageName.isEmpty || _isExtending) {
      await FlutterOverlayWindow.closeOverlay();
      return;
    }

    setState(() {
      _isExtending = true;
    });

    try {
      await UsageDataSaver.reload();

      final currentLimitMs = await UsageDataSaver.getLimit(_packageName);
      final todayUsageMs = await UsageDataSaver.getUsage(_packageName);

      final baseMs = currentLimitMs > todayUsageMs ? currentLimitMs : todayUsageMs;
      final newLimitMs = baseMs + (2 * 60000);

      // 1. New limit सेव करें
      final limitSaved = await UsageDataSaver.saveLimit(_packageName, newLimitMs);

      // Increment timeLeft by 2 minutes (snooze period)
      final currentLeft = await UsageDataSaver.getTimeLeft(_packageName);
      await UsageDataSaver.saveTimeLeft(_packageName, currentLeft + (2 * 60000));

      // 2. Snooze timestamp सेट करें (2 minutes from now)
      final snoozeUntil = DateTime.now()
          .add(const Duration(minutes: 2))
          .millisecondsSinceEpoch;
      final snoozeSaved = await UsageDataSaver.saveSnoozeUntil(_packageName, snoozeUntil);

      // 3. Blocked marker हटाएं
      if (limitSaved && snoozeSaved) {
        SharedPreferences preferences = await SharedPreferences.getInstance();
        await preferences.setString('active_foreground_package', _packageName);
        await preferences.remove(UsageDataSaver.activeBlockedPackage);

        try {
          final service = FlutterBackgroundService();
          service.invoke('limitChanged', {
            'packageName': _packageName,
            'snoozeUntil': snoozeUntil,
            'newLimitMs': newLimitMs,
          });
        } catch (e) {
          debugPrint('Error invoking limitChanged: $e');
        }

        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint("Error extending limit: $e");
    } finally {
      // FIX 2: क्लोज करने से पहले स्टेट को false करें ताकि अगली बार लोडर न दिखे
      if (mounted) {
        setState(() {
          _isExtending = false;
        });
      }
      await FlutterOverlayWindow.closeOverlay();
    }
  }
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_overlay_window/flutter_overlay_window.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// class OverlayWindow extends StatefulWidget {
//   const OverlayWindow({super.key});
//
//   @override
//   State<OverlayWindow> createState() => _OverlayWindowState();
// }
//
// class _OverlayWindowState extends State<OverlayWindow> {
//   String _appName = "This application";
//   String _packageName = "";
//   int _currentLimitMinutes = 0;
//   bool _isExtending = false; // prevent double-taps while write is in-flight
//   StreamSubscription? _dataSubscription;
//
//   @override
//   void initState() {
//     super.initState();
//     // Fallback: read from SharedPreferences immediately so something
//     // sensible shows even before real-time data arrives.
//     _loadOverlayData();
//
//     // NEW: Primary source of truth — the background service pushes the
//     // correct blocked-app info directly here via shareData(), right after
//     // showOverlay(). This avoids the SharedPreferences race that caused a
//     // stale app name (e.g. leftover "ChatGPT") to show for a different
//     // app's block.
//     _dataSubscription = FlutterOverlayWindow.overlayListener.listen((event) {
//       if (event is Map) {
//         final pkg = event['packageName'] as String?;
//         final name = event['appName'] as String?;
//         final limitMin = event['limitMinutes'] as int?;
//         if (pkg != null && pkg.isNotEmpty) {
//           setState(() {
//             _packageName = pkg;
//             _appName = name ?? pkg;
//             if (limitMin != null) _currentLimitMinutes = limitMin;
//           });
//         }
//       }
//     });
//   }
//
//   @override
//   void dispose() {
//     _dataSubscription?.cancel();
//     super.dispose();
//   }
//
//   Future<void> _loadOverlayData() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     final activePackage = prefs.getString('active_blocked_package') ?? '';
//     final activeName = prefs.getString('active_blocked_name') ?? 'This application';
//     final limitMs = prefs.getInt('limit_$activePackage') ?? 0;
//
//     setState(() {
//       _packageName = activePackage;
//       _appName = activeName;
//       _currentLimitMinutes = (limitMs / 60000).round();
//     });
//   }
//
//   Future<void> _extendLimit() async {
//     if (_packageName.isEmpty || _isExtending) {
//       await FlutterOverlayWindow.closeOverlay();
//       return;
//     }
//
//     setState(() {
//       _isExtending = true;
//     });
//
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.reload();
//
//       final currentLimitMs = prefs.getInt('limit_$_packageName') ?? 0;
//       final newLimitMs = currentLimitMs + (2 * 60000);
//
//       // 1. Persist the new limit and WAIT for confirmation it was written.
//       final limitSaved = await prefs.setInt('limit_$_packageName', newLimitMs);
//
//       // 2. Also set a time-based snooze as a safety net. Even if the
//       //    background service's usage math is briefly stale, it will not
//       //    re-trigger the overlay for this package until the snooze passes.
//       final snoozeUntil = DateTime.now()
//           .add(const Duration(minutes: 2))
//           .millisecondsSinceEpoch;
//       final snoozeSaved =
//       await prefs.setInt('snooze_until_$_packageName', snoozeUntil);
//
//       // 3. Clear the "currently blocked" marker only after the writes above
//       //    are confirmed, so the background service never reads a
//       //    half-updated state.
//       if (limitSaved && snoozeSaved) {
//         await prefs.remove('active_blocked_package');
//         // Small settle delay: SharedPreferences commits are async under the
//         // hood; this gives the platform channel time to flush before the
//         // background service's next poll (every 4s) reads it.
//         await Future.delayed(const Duration(milliseconds: 300));
//       }
//     } finally {
//       await FlutterOverlayWindow.closeOverlay();
//     }
//   }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.75), // Translucent backdrop
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.hourglass_bottom_rounded,
                  color: Colors.red.shade600,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              const Text(
                'Time Limit Reached',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                'You have used $_appName for $_currentLimitMinutes minutes today. Please take a break!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // Actions Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isExtending
                          ? null
                          : () async {
                        if (_packageName.isNotEmpty) {
                          try {
                            SharedPreferences preferences = await SharedPreferences.getInstance();
                            await preferences.remove(UsageDataSaver.activeBlockedPackage);
                            try {
                              final service = FlutterBackgroundService();
                              service.invoke('limitChanged', {
                                'packageName': _packageName,
                              });
                            } catch (e) {
                              debugPrint('Error invoking limitChanged from close: $e');
                            }
                            // Start launcher to go Home
                            await InstalledApps.startApp("com.example.testproject");
                            await Future.delayed(const Duration(milliseconds: 300));
                          } catch (e) {
                            debugPrint("Error going home on close: $e");
                          }
                        }
                        await FlutterOverlayWindow.closeOverlay();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Close',
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isExtending ? null : _extendLimit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isExtending
                          ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : const Text(
                        '+2 Minutes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}