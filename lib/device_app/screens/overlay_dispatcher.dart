import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localSaver/localSaver.dart';
import 'app_restrict_overlay.dart';
import 'overlay_window.dart';

class OverlayDispatcher extends StatefulWidget {
  const OverlayDispatcher({super.key});

  @override
  State<OverlayDispatcher> createState() => _OverlayDispatcherState();
}

class _OverlayDispatcherState extends State<OverlayDispatcher> {
  String _overlayType = 'block'; // Fallback
  String _packageName = "";
  String _appName = "this application";
  int _limitMinutes = 0;
  int _delaySeconds = 10;
  int _overlayId = 0; // Unique key to force recreation of child states
  StreamSubscription? _dataSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initAndLoad();

    // Single source of truth for the overlay listener
    _dataSubscription = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map) {
        final type = event['overlayType'] as String?;
        final pkg = event['packageName'] as String?;
        final name = event['appName'] as String?;
        final limitMin = event['limitMinutes'] as int?;
        final delaySecsVal = event['delaySeconds'] as int?;

        if (mounted) {
          setState(() {
            _overlayId = DateTime.now().millisecondsSinceEpoch; // Force key change
            if (type != null && type.isNotEmpty) {
              _overlayType = type;
            }
            if (pkg != null) {
              _packageName = pkg;
            }
            if (name != null) {
              _appName = name;
            }
            if (limitMin != null) {
              _limitMinutes = limitMin;
            }
            if (delaySecsVal != null) {
              _delaySeconds = delaySecsVal;
            }
          });
        }
      }
    });
  }

  Future<void> _initAndLoad() async {
    try {
      await _loadInitialState();
    } catch (e) {
      debugPrint("Error loading initial state: $e");
    } finally {
      if (mounted) {
        setState(() {
          _overlayId = DateTime.now().millisecondsSinceEpoch;
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  bool _isIgnoredPackage(String pkg) {
    if (pkg.isEmpty) return false;
    
    final lowerPkg = pkg.toLowerCase();
    
    if (lowerPkg == 'android') return true;
    if (lowerPkg == 'com.example.testproject') return true;
    
    if (lowerPkg.contains('launcher') ||
        lowerPkg.contains('home') ||
        lowerPkg.contains('systemui') ||
        lowerPkg.contains('settings') ||
        lowerPkg.contains('packageinstaller') ||
        lowerPkg.contains('permissioncontroller') ||
        lowerPkg.contains('inputmethod') ||
        lowerPkg.contains('keyboard') ||
        lowerPkg.contains('ime')) {
      return true;
    }
    
    return false;
  }

  Future<void> _loadInitialState() async {
    await UsageDataSaver.reload();
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString('active_overlay_type') ?? 'block';
    final activeForeground = prefs.getString('active_foreground_package') ?? '';
    final isAccessibilityEnabled = prefs.getBool('is_accessibility_enabled') ?? false;
    
    // Safety check: if overlay is restrict, but the user is already back on home/system UI
    if (isAccessibilityEnabled && type == 'restrict' && _isIgnoredPackage(activeForeground)) {
      debugPrint("[OverlayDispatcher] Closing overlay: active foreground package is ignored ($activeForeground)");
      await FlutterOverlayWindow.closeOverlay();
      return;
    }

    String pkg = "";
    String name = "this application";
    int limitMin = 0;
    int delaySecs = 10;

    if (type == 'restrict') {
      pkg = prefs.getString('active_restrict_package') ?? '';
      name = await UsageDataSaver.getAppName(pkg);
      delaySecs = prefs.getInt('delay_seconds_$pkg') ?? 10;
      
      // If the target package to restrict is no longer the active foreground package
      if (isAccessibilityEnabled && activeForeground.isNotEmpty && activeForeground != pkg) {
        debugPrint("[OverlayDispatcher] Closing overlay: target package is $pkg but foreground is $activeForeground");
        await FlutterOverlayWindow.closeOverlay();
        return;
      }
    } else {
      pkg = await UsageDataSaver.getActiveBlockedPackage() ?? '';
      name = await UsageDataSaver.getActiveBlockedName() ?? 'This application';
      final limitMs = await UsageDataSaver.getLimit(pkg);
      limitMin = (limitMs / 60000).round();
    }

    if (mounted) {
      setState(() {
        _overlayType = type;
        _packageName = pkg;
        _appName = name.isNotEmpty ? name : "this application";
        _limitMinutes = limitMin;
        _delaySeconds = delaySecs;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_overlayType == 'restrict') {
      return AppRestrictOverlay(
        key: ValueKey('restrict_$_overlayId'),
        initialPackageName: _packageName,
        initialAppName: _appName,
        initialDelaySeconds: _delaySeconds,
      );
    }

    return OverlayWindow(
      key: ValueKey('block_$_overlayId'),
      initialPackageName: _packageName,
      initialAppName: _appName,
      initialLimitMinutes: _limitMinutes,
    );
  }
}
