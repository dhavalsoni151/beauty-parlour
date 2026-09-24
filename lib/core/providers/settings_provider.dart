import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import 'firebase_startup_provider.dart';

class SettingsProvider extends ChangeNotifier {
  final FirestoreSettingsRepository _repository = FirestoreSettingsRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  Map<String, String> _settings = {};
  bool _isLoaded = false;
  StreamSubscription<Map<String, String>>? _subscription;

  bool get isLoaded => _isLoaded;
  String get parlourName => _settings['parlour_name'] ?? 'Priyanka Beauty Parlour';
  String get ownerName => _settings['owner_name'] ?? '';
  String get phone => _settings['phone'] ?? '';
  String get address => _settings['address'] ?? '';
  String get currency => _settings['currency'] ?? '₹';
  String get defaultPaymentMethod => _settings['default_payment_method'] ?? 'CASH';

  String? get scannerImagePath {
    final path = _settings['scanner_image_path'];
    return (path == null || path.isEmpty) ? null : path;
  }

  Future<void> setScannerImage(String path) async {
    await _repository.set('scanner_image_path', path);
  }

  Future<void> clearScannerImage() async {
    await _repository.delete('scanner_image_path');
  }

  bool get isPinEnabled => _settings['pin_enabled'] == 'true' && hasPin;
  bool get hasPin => (_settings['pin_hash'] ?? '').isNotEmpty;

  String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<void> setPin(String pin) async {
    final hash = _hashPin(pin);
    await _repository.set('pin_hash', hash);
    await _repository.set('pin_enabled', 'true');
  }

  Future<void> disablePin() async {
    await _repository.set('pin_enabled', 'false');
    await _repository.delete('pin_hash');
  }

  bool verifyPin(String pin) => hasPin && _hashPin(pin) == _settings['pin_hash'];

  Future<void> loadSettings() async {
    _settings = await _repository.getAll();
    _subscription?.cancel();
    _subscription = _repository.watchAll().listen((values) {
      _settings = values;
      _isLoaded = true;
      notifyListeners();
    });
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> updateSetting(String key, String value) =>
      _repository.set(key, value);

  Future<void> updateAll({
    required String parlourName,
    required String ownerName,
    required String phone,
    required String address,
  }) async {
    await _repository.set('parlour_name', parlourName);
    await _repository.set('owner_name', ownerName);
    await _repository.set('phone', phone);
    await _repository.set('address', address);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
