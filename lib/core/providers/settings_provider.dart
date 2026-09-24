import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../database/database.dart';

class SettingsProvider extends ChangeNotifier {
  final _settingsDao = SettingsDao();
  Map<String, String> _settings = {};
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  String get parlourName => _settings['parlour_name'] ?? 'Priyanka Beauty Parlour';
  String get ownerName => _settings['owner_name'] ?? '';
  String get phone => _settings['phone'] ?? '';
  String get address => _settings['address'] ?? '';
  String get currency => _settings['currency'] ?? '₹';
  String get defaultPaymentMethod => _settings['default_payment_method'] ?? 'CASH';

  // ── Payment scanner (QR code) image ──────────────────────────────────────

  /// Local file path of the uploaded payment scanner (UPI QR code) image, so
  /// it can be shown to customers when they choose to pay by scanning it.
  String? get scannerImagePath {
    final path = _settings['scanner_image_path'];
    return (path == null || path.isEmpty) ? null : path;
  }

  Future<void> setScannerImage(String path) async {
    await _settingsDao.setSetting('scanner_image_path', path);
    _settings['scanner_image_path'] = path;
    notifyListeners();
  }

  Future<void> clearScannerImage() async {
    await _settingsDao.deleteSetting('scanner_image_path');
    _settings.remove('scanner_image_path');
    notifyListeners();
  }

  // ── App PIN lock ─────────────────────────────────────────────────────────

  bool get isPinEnabled => _settings['pin_enabled'] == 'true' && hasPin;
  bool get hasPin => (_settings['pin_hash'] ?? '').isNotEmpty;

  String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

  /// Sets (or changes) the app-unlock PIN and enables the lock.
  Future<void> setPin(String pin) async {
    final hash = _hashPin(pin);
    await _settingsDao.setSetting('pin_hash', hash);
    await _settingsDao.setSetting('pin_enabled', 'true');
    _settings['pin_hash'] = hash;
    _settings['pin_enabled'] = 'true';
    notifyListeners();
  }

  /// Disables the PIN lock (forgets the stored PIN entirely).
  Future<void> disablePin() async {
    await _settingsDao.setSetting('pin_enabled', 'false');
    await _settingsDao.deleteSetting('pin_hash');
    _settings['pin_enabled'] = 'false';
    _settings.remove('pin_hash');
    notifyListeners();
  }

  bool verifyPin(String pin) => hasPin && _hashPin(pin) == _settings['pin_hash'];

  Future<void> loadSettings() async {
    _settings = await _settingsDao.getSettings();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> updateSetting(String key, String value) async {
    await _settingsDao.setSetting(key, value);
    _settings[key] = value;
    notifyListeners();
  }

  Future<void> updateAll({
    required String parlourName,
    required String ownerName,
    required String phone,
    required String address,
  }) async {
    await _settingsDao.setSetting('parlour_name', parlourName);
    await _settingsDao.setSetting('owner_name', ownerName);
    await _settingsDao.setSetting('phone', phone);
    await _settingsDao.setSetting('address', address);
    _settings['parlour_name'] = parlourName;
    _settings['owner_name'] = ownerName;
    _settings['phone'] = phone;
    _settings['address'] = address;
    notifyListeners();
  }
}
