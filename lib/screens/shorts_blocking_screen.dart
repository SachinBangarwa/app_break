import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';

class ShortsBlockingScreen extends StatefulWidget {
  const ShortsBlockingScreen({super.key});

  @override
  State<ShortsBlockingScreen> createState() => _ShortsBlockingScreenState();
}

class _ShortsBlockingScreenState extends State<ShortsBlockingScreen> {
  // 7 items: [Instagram Reels (0), Instagram Stories (1), YouTube Shorts (2), Facebook Reels (3), Facebook Stories (4), Snapchat Spotlight (5), Snapchat Stories (6)]
  List<int> _shortsList = [0, 0, 0, 0, 0, 0, 0];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShortsList();
  }

  Future<void> _loadShortsList() async {
    final list = await UsageDataSaver.getShortsBlockingList();
    if (mounted) {
      setState(() {
        if (list.length >= 7) {
          _shortsList = List<int>.from(list.sublist(0, 7));
        } else {
          _shortsList = List<int>.from(list);
          while (_shortsList.length < 7) {
            _shortsList.add(0);
          }
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleOption(int index) async {
    setState(() {
      _shortsList[index] = _shortsList[index] == 1 ? 0 : 1;
    });
    await UsageDataSaver.saveShortsBlockingList(_shortsList);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Back Arrow & Title
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
                  const Text(
                    'Blocking',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Content List Grouped by App Category Cards
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Instagram Category Card
                        _buildCategoryCard(
                          appName: 'Instagram',
                          appIcon: Icons.camera_alt_rounded,
                          switches: [
                            {
                              'title': 'Block Instagram Reels',
                              'index': 0,
                            },
                            {
                              'title': 'Block Instagram Stories',
                              'index': 1,
                            },
                          ],
                        ),
                        const SizedBox(height: 24),

                        // YouTube Category Card
                        _buildCategoryCard(
                          appName: 'YouTube',
                          appIcon: Icons.play_circle_fill_rounded,
                          switches: [
                            {
                              'title': 'Block YouTube Shorts',
                              'index': 2,
                            },
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Facebook Category Card
                        _buildCategoryCard(
                          appName: 'Facebook',
                          appIcon: Icons.facebook_rounded,
                          switches: [
                            {
                              'title': 'Block Facebook Reels',
                              'index': 3,
                            },
                            {
                              'title': 'Block Facebook Stories',
                              'index': 4,
                            },
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Snapchat Category Card
                        _buildCategoryCard(
                          appName: 'Snapchat',
                          appIcon: Icons.chat_bubble_outline_rounded,
                          switches: [
                            {
                              'title': 'Block Snapchat Spotlight',
                              'index': 5,
                            },
                            {
                              'title': 'Block Snapchat Stories',
                              'index': 6,
                            },
                          ],
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard({
    required String appName,
    required IconData appIcon,
    required List<Map<String, dynamic>> switches,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(appIcon, size: 20, color: Colors.black),
            const SizedBox(width: 8),
            Text(
              appName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1.0,
            ),
          ),
          child: Column(
            children: switches.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final title = item['title'] as String;
              final switchIndex = item['index'] as int;
              final bool isEnabled = _shortsList[switchIndex] == 1;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          child: Icon(
                            appIcon,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: isEnabled,
                          activeTrackColor: Colors.black,
                          onChanged: (_) => _toggleOption(switchIndex),
                        ),
                      ],
                    ),
                  ),
                  if (idx < switches.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF3F4F6),
                      indent: 64,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
