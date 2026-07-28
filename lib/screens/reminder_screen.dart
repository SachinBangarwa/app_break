import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:testproject/device_app/localSaver/active_apps_manager.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  int _selectedOption = 0; // Default: 0 ("Always ask reminder time")
  bool _isLoading = true;

  final List<Map<String, dynamic>> _reminderOptions = const [
    {'label': 'Always show', 'value': -1},
    {'label': 'Always ask reminder time', 'value': 0},
    {'label': '1 min', 'value': 1},
    {'label': '3 min', 'value': 3},
    {'label': '5 min', 'value': 5},
    {'label': '10 min', 'value': 10},
    {'label': '15 min', 'value': 15},
    {'label': '20 min', 'value': 20},
    {'label': '30 min', 'value': 30},
    {'label': '45 min', 'value': 45},
    {'label': '1 hour', 'value': 60},
    {'label': '90 min', 'value': 90},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedOption();
  }

  Future<void> _loadSavedOption() async {
    final option = await UsageDataSaver.getReminderOption();
    if (mounted) {
      setState(() {
        _selectedOption = option;
        _isLoading = false;
      });
    }
  }

  Future<void> _onOptionSelected(int value) async {
    setState(() {
      _selectedOption = value;
    });

    // 1. Save to SharedPreferences (Persistent local disk)
    await UsageDataSaver.saveReminderOption(value);

    // 2. Update RAM memory cache immediately
    ActiveAppsManager.reminderOptionSetting = value;

    // 3. Sync to background service RAM memory via IPC
    try {
      final isRunning = await FlutterBackgroundService().isRunning();
      if (isRunning) {
        FlutterBackgroundService().invoke('syncReminderOption', {'option': value});
      }
    } catch (_) {}
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Reminder Setting"),
        content: const Text(
          "Choose how App Break handles session reminders:\n\n"
          "• Always show: Show overlay every time app is opened.\n"
          "• Always ask: Asks you how long you need the app every time.\n"
          "• Custom time (e.g. 5 min): Automatically applies the selected session duration.",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
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
                      'Reminder',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showInfoDialog(context),
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

            // Content Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        const Text(
                          "Time",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Set reminder time when you will face Pause Screen repeatedly to avoid getting stuck inside a distracting app",
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Options Card
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18.0),
                            border: Border.all(
                              color: const Color(0xFFE5E7EB),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            children: _reminderOptions.asMap().entries.map((entry) {
                              final index = entry.key;
                              final opt = entry.value;
                              final label = opt['label'] as String;
                              final val = opt['value'] as int;
                              final isSelected = _selectedOption == val;

                              return Column(
                                children: [
                                  InkWell(
                                    onTap: () => _onOptionSelected(val),
                                    borderRadius: BorderRadius.circular(18.0),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 14.0,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isSelected
                                                    ? Colors.black
                                                    : const Color(0xFF9CA3AF),
                                                width: isSelected ? 6.5 : 1.8,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (index < _reminderOptions.length - 1)
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Color(0xFFF3F4F6),
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
