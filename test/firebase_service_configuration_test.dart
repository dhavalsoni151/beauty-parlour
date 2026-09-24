import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:beauty_parlour/core/firebase/firebase_service.dart';

void main() {
  test('firebase service offline settings enable persistence and unlimited cache',
      () {
    const settings = FirebaseService.offlineSettings;
    expect(settings.persistenceEnabled, isTrue);
    expect(settings.cacheSizeBytes, Settings.CACHE_SIZE_UNLIMITED);
  });
}
