/// Barrel export for the database access layer (AppDatabase + DAOs).
/// Import this from providers/services instead of individual DAO files.
export 'app_database.dart';
export 'migration_mapping.dart';
export 'daos/db_exceptions.dart';
export 'daos/settings_dao.dart';
export 'daos/customer_dao.dart';
export 'daos/category_dao.dart';
export 'daos/service_type_dao.dart';
export 'daos/service_dao.dart';
export 'daos/visit_dao.dart';
export 'daos/payment_dao.dart';
export 'daos/write_off_dao.dart';
export 'daos/expense_dao.dart';
export 'daos/report_dao.dart';
export 'daos/backup_service.dart';
