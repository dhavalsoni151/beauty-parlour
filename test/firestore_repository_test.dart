import 'package:flutter_test/flutter_test.dart';
import 'package:beauty_parlour/core/firestore/firestore_repositories.dart';
import 'package:beauty_parlour/core/models/visit_models.dart';

void main() {
  test('legacy ids become deterministic Firestore document ids', () {
    expect(FirestoreModelCodec.documentId(legacyId: 42), '42');
    expect(FirestoreModelCodec.documentId(legacyId: 0), '0');
  });

  test('master records carry migration metadata without changing fields', () {
    final fields = <String, dynamic>{
      'id': 7,
      'name': 'Full Hands',
      'default_price': 170.0,
    };

    final record = FirestoreModelCodec.record(fields, legacyId: 7);

    expect(record['legacy_id'], 7);
    expect(record['record_type'], 'master_data');
    expect(record['schema_version'], FirestoreModelCodec.schemaVersion);
    expect(record['name'], 'Full Hands');
    expect(record['default_price'], 170.0);
  });

  test('historical records are marked without rewriting snapshots', () {
    const service = VisitService(
      visitId: 12,
      serviceId: 3,
      categoryId: 1,
      serviceTypeId: 2,
      categoryNameSnapshot: 'Wax',
      serviceTypeNameSnapshot: 'Rica Wax',
      serviceNameSnapshot: 'Full Hands',
      price: 250,
      total: 250,
    );

    final record = FirestoreModelCodec.historical(
      service.toMap(),
      legacyId: 19,
    );

    expect(record['record_type'], 'historical_transaction');
    expect(record['legacy_id'], 19);
    expect(record['category_name_snapshot'], 'Wax');
    expect(record['service_type_name_snapshot'], 'Rica Wax');
    expect(record['service_name_snapshot'], 'Full Hands');
    expect(record['price'], 250);
  });

  test('organization scope rejects an empty organization id', () {
    expect(
      () => FirestoreScope.validateOrganizationId(''),
      throwsArgumentError,
    );
  });
}
