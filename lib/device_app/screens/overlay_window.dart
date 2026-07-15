
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:installed_apps/installed_apps.dart';
class OverlayWindow extends StatefulWidget {
  final String initialPackageName;
  final String initialAppName;
  final int initialLimitMinutes;
  final int initialLimitMs;
  final int initialTodayUsageMs;

  const OverlayWindow({
    super.key,
    this.initialPackageName = "",
    this.initialAppName = "This application",
    this.initialLimitMinutes = 0,
    this.initialLimitMs = 0,
    this.initialTodayUsageMs = 0,
  });

  @override
  State<OverlayWindow> createState() => _OverlayWindowState();
}
class _OverlayWindowState extends State<OverlayWindow> {
  String _appName = "This application";
  String _packageName = "";
  int _currentLimitMinutes = 0;
  bool _isExtending = false;

  int _limitMs = 0;
  int _todayUsageMs = 0;

  @override
  void initState() {
    super.initState();
    _packageName = widget.initialPackageName;
    _appName = widget.initialAppName;
    _currentLimitMinutes = widget.initialLimitMinutes;
    _limitMs = widget.initialLimitMs > 0 ? widget.initialLimitMs : (widget.initialLimitMinutes * 60000);
    _todayUsageMs = widget.initialTodayUsageMs;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OverlayWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPackageName != oldWidget.initialPackageName ||
        widget.initialAppName != oldWidget.initialAppName ||
        widget.initialLimitMinutes != oldWidget.initialLimitMinutes ||
        widget.initialLimitMs != oldWidget.initialLimitMs ||
        widget.initialTodayUsageMs != oldWidget.initialTodayUsageMs) {
      setState(() {
        _packageName = widget.initialPackageName;
        _appName = widget.initialAppName;
        _currentLimitMinutes = widget.initialLimitMinutes;
        _limitMs = widget.initialLimitMs > 0 ? widget.initialLimitMs : (widget.initialLimitMinutes * 60000);
        _todayUsageMs = widget.initialTodayUsageMs;
        _isExtending = false;
      });
    }
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
      final baseMs = _limitMs > _todayUsageMs ? _limitMs : _todayUsageMs;
      final newLimitMs = baseMs + (2 * 60000);

      // Invoke event in background service to update DB and RAM list
      final service = FlutterBackgroundService();
      service.invoke('extendLimit', {
        'packageName': _packageName,
        'newLimitMs': newLimitMs,
      });

      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint("Error extending limit: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isExtending = false;
        });
      }
      await FlutterOverlayWindow.closeOverlay();
    }
  }


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