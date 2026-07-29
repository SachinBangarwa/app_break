import 'package:flutter/material.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';

class AddWebsiteScreen extends StatefulWidget {
  final bool isForBlocking;
  const AddWebsiteScreen({super.key, this.isForBlocking = false});

  @override
  State<AddWebsiteScreen> createState() => _AddWebsiteScreenState();
}

class _AddWebsiteScreenState extends State<AddWebsiteScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isSaving = false;

  Future<void> _saveWebsite() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSaving = true;
    });

    if (widget.isForBlocking) {
      await AppDbHelper.instance.addBlockedWebsite(text);
    } else {
      await AppDbHelper.instance.addWebsite(text);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Close Button & Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.black,
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Add website',
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

            // Header Description
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
              child: Text(
                'Add a website by entering a domain name, for example: instagram.com or by pasting a link from your browser: https://www.instagram.com/',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Input Field (Autofocused for immediate keyboard entry)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: Colors.black,
                    width: 1.2,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveWebsite(),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter link or domain name',
                    hintStyle: TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),

            const Spacer(),

            // Save Button at bottom
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveWebsite,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
