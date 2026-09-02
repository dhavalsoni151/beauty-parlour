import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/database/database_helper.dart';
import '../../shared/widgets/app_widgets.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_rounded, color: AppColors.info, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'Backup saves all your data as a JSON file. Store it safely in Google Drive or send it to yourself.',
                  style: TextStyle(fontSize: 13, color: AppColors.info),
                )),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Backup section
          const Text('BACKUP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          _buildCard([
            _buildActionTile(
              Icons.cloud_upload_rounded,
              'Create Backup',
              'Export all data as a JSON file',
              AppColors.info,
              _createBackup,
            ),
          ]),
          const SizedBox(height: 20),

          // Restore section
          const Text('RESTORE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_rounded, color: AppColors.error, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text(
                  'Restoring from backup will replace ALL existing data. This cannot be undone!',
                  style: TextStyle(fontSize: 13, color: AppColors.error),
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildCard([
            _buildActionTile(
              Icons.cloud_download_rounded,
              'Restore from Backup',
              'Select a backup file to restore',
              AppColors.error,
              _restoreBackup,
            ),
          ]),

          if (_isLoading) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],

          if (_statusMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusMessage.contains('Error') ? AppColors.errorLight : AppColors.successLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusMessage.contains('Error') ? Icons.error_rounded : Icons.check_circle_rounded,
                    color: _statusMessage.contains('Error') ? AppColors.error : AppColors.success,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_statusMessage,
                    style: TextStyle(
                      fontSize: 13,
                      color: _statusMessage.contains('Error') ? AppColors.error : AppColors.success,
                    ))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildActionTile(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: _isLoading ? AppColors.textHint : color),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() { _isLoading = true; _statusMessage = ''; });
    try {
      final data = await DatabaseHelper.instance.exportAllData();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now();
      final fileName = 'beauty_parlour_backup_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}.json';

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(json);

      // Share file
      await Share.shareXFiles([XFile(file.path)], subject: 'Beauty Parlour Backup', text: 'Backup created on ${now.day}/${now.month}/${now.year}');

      setState(() { _statusMessage = 'Backup created: $fileName'; });
    } catch (e) {
      setState(() { _statusMessage = 'Error creating backup: $e'; });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreBackup() async {
    // Confirm
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Restore Backup',
      message: 'This will REPLACE all existing data with the backup. Are you sure?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;

    setState(() { _isLoading = true; _statusMessage = ''; });
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.path == null) {
        setState(() => _isLoading = false);
        return;
      }

      final file = File(result.path!);
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      await DatabaseHelper.instance.importAllData(data);
      setState(() { _statusMessage = 'Backup restored successfully!'; });
    } catch (e) {
      setState(() { _statusMessage = 'Error restoring backup: $e'; });
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
