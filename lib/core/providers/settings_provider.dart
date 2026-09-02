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
