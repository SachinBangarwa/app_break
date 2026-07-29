import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';

class FocusActiveSessionScreen extends StatefulWidget {
  final int startTimeMs;
  final int durationMinutes;

  const FocusActiveSessionScreen({
    super.key,
    required this.startTimeMs,
    required this.durationMinutes,
  });

  @override
  State<FocusActiveSessionScreen> createState() => _FocusActiveSessionScreenState();
}

class _FocusActiveSessionScreenState extends State<FocusActiveSessionScreen> {
  Timer? _timer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _calculateRemainingTime();
    _startTimer();
  }

  void _calculateRemainingTime() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final totalSeconds = widget.durationMinutes * 60;
    final elapsedSeconds = ((nowMs - widget.startTimeMs) / 1000).floor();
    final remaining = totalSeconds - elapsedSeconds;

    if (remaining <= 0) {
      _remainingSeconds = 0;
      _stopSessionAndClose(isCompleted: true);
    } else {
      _remainingSeconds = remaining;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingSeconds > 1) {
            _remainingSeconds--;
          } else {
            _remainingSeconds = 0;
            timer.cancel();
            _stopSessionAndClose(isCompleted: true);
          }
        });
      }
    });
  }

  Future<void> _stopSessionAndClose({bool isCompleted = false}) async {
    _timer?.cancel();
    await UsageDataSaver.clearFocusSessionStart();
    if (mounted) {
      if (isCompleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Focus Session completed! Great job! 🎉'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      Navigator.pop(context);
    }
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            children: [
              const Spacer(),

              // Center Content: Shield Icon, Title, Live Timer
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Shield Icon with Heart inside
                  Stack(
                    alignment: Alignment.center,
                    children: const [
                      Icon(
                        Icons.shield_outlined,
                        size: 92,
                        color: Colors.black,
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Icon(
                          Icons.favorite_rounded,
                          size: 32,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Title: Stay focused
                  const Text(
                    'Stay focused',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Timer Display: e.g. 44:58
                  Text(
                    _formatTimerText(_remainingSeconds),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Bottom Action Buttons: Close app & Stop Focus Session
              Column(
                children: [
                  // Close App Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        SystemNavigator.pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(
                          color: Colors.black,
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                      child: const Text(
                        'Close app',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Stop Focus Session Link
                  TextButton(
                    onPressed: () => _stopSessionAndClose(isCompleted: false),
                    child: const Text(
                      'Stop Focus Session',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
