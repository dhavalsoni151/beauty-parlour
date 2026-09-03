import 'package:flutter/foundation.dart';

/// Tracks whether the app is currently showing the PIN-lock screen.
///
/// This is purely in-memory session state (not persisted): every cold start
/// begins locked (if a PIN is configured), and the app is re-locked whenever
/// it is sent to the background, so the PIN is required "every time" the app
/// is opened/resumed, per the product requirement.
class AppLockProvider extends ChangeNotifier {
  bool _isLocked = true;

  bool get isLocked => _isLocked;

  void lock() {
    if (_isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_isLocked) return;
    _isLocked = false;
    notifyListeners();
  }
}
