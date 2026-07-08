import 'dart:async';
import 'package:flutter/material.dart';

class AppLaunchDelayDialog extends StatefulWidget {
  final String appName;
  final VoidCallback onCountdownComplete;

  const AppLaunchDelayDialog({
    super.key,
    required this.appName,
    required this.onCountdownComplete,
  });

  @override
  State<AppLaunchDelayDialog> createState() => _AppLaunchDelayDialogState();
}

class _AppLaunchDelayDialogState extends State<AppLaunchDelayDialog> {
  int _secondsRemaining = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        Navigator.of(context).pop(); // Close the dialog
        widget.onCountdownComplete(); // Launch the target application
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.hourglass_empty_rounded,
                color: theme.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Opening ${widget.appName}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Starting in $_secondsRemaining seconds...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
