import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/firebase/firebase_service.dart';
import '../../core/firestore/firestore_migration.dart';
import '../../core/firestore/firestore_repositories.dart';
import '../../core/providers/firebase_startup_provider.dart';
import '../../core/theme/app_theme.dart';

class FirestoreMigrationAuthorization {
  static Future<String?> currentRole() async {
    final service = FirebaseService.instance;
    final user = service.auth.currentUser;
    if (user == null) return null;
    await service.requireOnline();
    final member = await service.firestore
        .collection('organizations')
        .doc(firebaseOrganizationId)
        .collection('members')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));
    if (!member.exists) return null;
    final role = member.data()?['role'] as String?;
    return role == 'owner' || role == 'admin' ? role : null;
  }
}

class FirestoreMigrationScreen extends StatefulWidget {
  const FirestoreMigrationScreen({super.key});

  @override
  State<FirestoreMigrationScreen> createState() => _FirestoreMigrationScreenState();
}

class _FirestoreMigrationScreenState extends State<FirestoreMigrationScreen> {
  FirestoreMigrationPlan? _plan;
  FirestoreMigrationReadback? _readback;
  String? _fileName;
  String? _error;
  String _status = 'Select the authoritative JSON backup to begin a dry run.';
  int _completed = 0;
  bool _checkingAccess = true;
  bool _authorized = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    try {
      final role = await FirestoreMigrationAuthorization.currentRole();
      if (!mounted) return;
      setState(() {
        _authorized = role != null;
        _checkingAccess = false;
        _status = role == null ? 'Only the owner or an admin can migrate data.' : 'Authorized as $role.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingAccess = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _selectBackup() async {
    setState(() {
      _busy = true;
      _error = null;
      _plan = null;
      _readback = null;
      _status = 'Reading backup for dry-run validation...';
    });
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (files.isEmpty || files.first.path == null) {
        setState(() { _busy = false; _status = 'No backup selected.'; });
        return;
      }
      final selected = files.first;
      final file = File(selected.path!);
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) throw const FormatException('Backup root must be a JSON object.');
      final plan = FirestoreMigrationPlanner().build(
        json,
        organizationId: firebaseOrganizationId,
      );
      if (!mounted) return;
      setState(() {
        _fileName = selected.name;
        _plan = plan;
        _busy = false;
        _status = plan.isSafe ? 'Dry run passed. Review the report before continuing.' : 'Dry run failed. No writes are permitted.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _busy = false; _error = error.toString(); _status = 'Dry run failed.'; });
    }
  }

  Future<void> _execute() async {
    final plan = _plan;
    if (plan == null || !plan.isSafe || _busy) return;
    final confirmed = await _confirmWrites();
    if (!confirmed || !mounted) return;
    setState(() { _busy = true; _error = null; _status = 'Starting resumable migration...'; });
    try {
      final scope = FirestoreScope(
        firestore: FirebaseService.instance.firestore,
        organizationId: firebaseOrganizationId,
      );
      final executor = FirestoreMigrationExecutor(scope);
      await executor.apply(
        plan,
        confirm: true,
        onProgress: (completed, total, status) {
          if (!mounted) return;
          setState(() { _completed = completed; _status = '$status ($completed/$total)'; });
        },
      );
      final readback = await executor.reconcile(plan);
      if (!mounted) return;
      setState(() {
        _readback = readback;
        _busy = false;
        _status = readback.matchesPlan(plan) ? 'Migration and reconciliation succeeded.' : 'Migration completed but reconciliation failed.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _busy = false; _error = error.toString(); _status = 'Migration stopped. Resume is safe after the error is resolved.'; });
    }
  }

  Future<bool> _confirmWrites() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Firestore migration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This writes the validated backup to Firestore. SQLite will not be changed.'),
            const SizedBox(height: 16),
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Type MIGRATE to continue')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim() == 'MIGRATE'), child: const Text('Write data')),
        ],
      ),
    );
    controller.dispose();
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_authorized) return _message('Migration unavailable', _error ?? _status);
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Firestore Migration')),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _message('Migration status', _status),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _message('Error', _error!, color: AppColors.error),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _selectBackup,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(_fileName == null ? 'Select JSON backup for dry run' : 'Select a different backup'),
          ),
          if (plan != null) ...[
            const SizedBox(height: 16),
            _reportCard(plan),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _busy || !plan.isSafe ? null : _execute,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('Run confirmed migration'),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: plan == null || plan.writeCount == 0 ? null : _completed / plan.writeCount),
          ],
          if (_readback != null) ...[
            const SizedBox(height: 16),
            _message(
              _readback!.matchesPlan(plan!) ? 'Reconciliation succeeded' : 'Reconciliation failed',
              _readback!.matchesPlan(plan) ? 'All records, snapshots, counts, and financial totals match.' : 'Review missing or mismatched records before any cutover.',
              color: _readback!.matchesPlan(plan) ? AppColors.success : AppColors.error,
            ),
          ],
        ],
      ),
    );
  }

  Widget _reportCard(FirestoreMigrationPlan plan) {
    final validation = plan.validation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(plan.isSafe ? 'Dry run passed' : 'Dry run failed', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Operations: ${plan.writeCount}'),
          Text('Fingerprint: ${plan.sourceFingerprint}'),
          Text('Billed: ₹${validation.sourceVisitsTotal.toStringAsFixed(2)}'),
          Text('Paid: ₹${validation.sourcePaymentsTotal.toStringAsFixed(2)}'),
          Text('Expenses: ₹${validation.sourceExpensesTotal.toStringAsFixed(2)}'),
          if (validation.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...validation.warnings.map((warning) => Text(warning, style: const TextStyle(color: AppColors.warning))),
          ],
          if (validation.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...validation.errors.map((error) => Text(error, style: const TextStyle(color: AppColors.error))),
          ],
        ]),
      ),
    );
  }

  Widget _message(String title, String message, {Color? color}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color ?? AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(message),
          ]),
        ),
      );
}