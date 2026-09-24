import 'package:flutter_test/flutter_test.dart';
import 'package:beauty_parlour/core/firestore/firestore_repositories.dart';

void main() {
  test('generated numeric ids are positive and unique across calls', () {
    final a = FirestoreModelCodec.numericId();
    final b = FirestoreModelCodec.numericId();
    expect(a, greaterThan(0));
    expect(b, greaterThan(0));
    expect(a == b, isFalse);
  });


  test('numeric id generator produces unique values across burst sample', () {
    final values = <int>{};
    for (var i = 0; i < 5000; i++) {
      values.add(FirestoreModelCodec.numericId());
    }
    expect(values.length, 5000);
  });

  test('document-id derivation is deterministic', () {
    final first = FirestoreModelCodec.deriveIdFromDocumentId('abc123');
    final second = FirestoreModelCodec.deriveIdFromDocumentId('abc123');
    final third = FirestoreModelCodec.deriveIdFromDocumentId('xyz789');
    expect(first, equals(second));
    expect(first, isNot(equals(third)));
    expect(first, greaterThan(0));
  });

  test('organization scope rejects an empty organization id', () {
    expect(
      () => FirestoreScope.validateOrganizationId(''),
      throwsArgumentError,
    );
  });
}
