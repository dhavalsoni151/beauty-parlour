import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';

/// Shared helper for the "preview, then send via WhatsApp" flow used across
/// Packages and Services sharing. Nothing is sent automatically — the
/// message is shown (and editable) first, and the actual send happens
/// through the OS share sheet (which includes WhatsApp) via [Share.share].
class WhatsAppShare {
  WhatsAppShare._();

  /// Shows a preview dialog with the given [message] (editable) and shares
  /// it through the device share sheet when the user taps "Share on
  /// WhatsApp". Returns true if the user went ahead and shared.
  static Future<bool> previewAndSend(
    BuildContext context, {
    required String title,
    required String message,
    String subject = 'Beauty Parlour',
  }) async {
    final controller = TextEditingController(text: message);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review the message below before sharing. You can edit it here.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: null,
                  minLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Share on WhatsApp'),
          ),
        ],
      ),
    );

    if (result != true) {
      controller.dispose();
      return false;
    }

    final finalMessage = controller.text.trim();
    controller.dispose();
    if (finalMessage.isEmpty) return false;
    await Share.share(finalMessage, subject: subject);
    return true;
  }
}
