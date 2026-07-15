import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'app_restrict_overlay.dart';
import 'overlay_window.dart';

class OverlayDispatcher extends StatefulWidget {
  const OverlayDispatcher({super.key});

  @override
  State<OverlayDispatcher> createState() => _OverlayDispatcherState();
}

class _OverlayDispatcherState extends State<OverlayDispatcher> {
  String _overlayType = 'block';
  String _packageName = "";
  String _appName = "this application";
  int _limitMinutes = 0;
  int _delaySeconds = 10;
  int _limitMs = 0;
  int _todayUsageMs = 0;
  int _overlayId = 0;
  StreamSubscription? _dataSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _dataSubscription = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map) {
        final type = event['overlayType'] as String?;
        final pkg = event['packageName'] as String?;
        final name = event['appName'] as String?;
        final limitMin = event['limitMinutes'] as int?;
        final limitMs = event['limitMs'] as int?;
        final todayUsageMs = event['todayUsageMs'] as int?;
        final delaySecsVal = event['delaySeconds'] as int?;

        if (mounted) {
          setState(() {
            _isLoading = false;
            _overlayId = DateTime.now().millisecondsSinceEpoch;
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
            if (limitMs != null) {
              _limitMs = limitMs;
            }
            if (todayUsageMs != null) {
              _todayUsageMs = todayUsageMs;
            }
            if (delaySecsVal != null) {
              _delaySeconds = delaySecsVal;
            }
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
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
      initialLimitMs: _limitMs,
      initialTodayUsageMs: _todayUsageMs,
    );
  }
}
