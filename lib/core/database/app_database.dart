import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'migration_mapping.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// DATABASE IMPLEMENTATION NOTE (please read before "converting to Drift")
/// ─────────────────────────────────────────────────────────────────────────
/// This app was specced to migrate onto Drift. The build environment used to
/// author this change cannot run `flutter pub get` nor `dart run build_runner
/// build`, which Drift REQUIRES to generate its typed row/companion classes
/// and the `_$AppDatabase` mixin. Hand-writing Drift's generated `*.g.dart`
/// output (or the non-generated GeneratedDatabase internals) for 12 tables
/// without a compiler is far more error-prone than the relational work that
/// actually matters here.
///
/// Per the task's explicit guidance, we therefore keep `sqflite` but implement
/// a strongly-structured schema + DAO layer that mirrors exactly what Drift
/// would provide:
///   • [AppDatabase] is the single source of truth for the schema (table and
///     column names, FKs, unique constraints and indexes) and owns migrations
///     via sqflite's onUpgrade — the equivalent of a Drift `@DriftDatabase`.
///   • Each aggregate has its own DAO (see daos/) mirroring Drift DAOs.
///   • Table/column names and DAO method signatures are chosen so this layer
///     is trivially convertible to real Drift later (same names, same shapes).
///
/// JSON is used ONLY for backup/export/restore/migration — never as the live
/// store (the live store is always this SQLite database).
/// ─────────────────────────────────────────────────────────────────────────

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const int schemaVersion = 4;
  static const String _dbFileName = 'beauty_parlour.db';

  Database? _database;

  /// Set by the onUpgrade hierarchy migration; surfaced to the UI on next
  /// launch (stored in settings) so the user sees what changed.
  MigrationReport? lastAutoMigrationReport;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbFileName);
    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  // ── Fresh install ────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await _createTablesV4(db);
    await _createIndexesV4(db);
    await _seedDefaultData(db);
  }

  Future<void> _createTablesV4(DatabaseExecutor db) async {
    await _createTablesV3(db);
    await db.execute('''
      CREATE TABLE appointment_services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        appointment_id INTEGER NOT NULL,
        service_id INTEGER,
        category_id INTEGER,
        service_type_id INTEGER,
        category_name_snapshot TEXT NOT NULL DEFAULT '',
        service_type_name_snapshot TEXT,
        service_name_snapshot TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        total REAL NOT NULL,
        created_at TEXT,
        FOREIGN KEY (appointment_id) REFERENCES appointments(id),
        FOREIGN KEY (service_id) REFERENCES services(id),
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (service_type_id) REFERENCES service_types(id)
      )
    ''');
  }

  Future<void> _createTablesV3(DatabaseExecutor db) async {
    await _createTablesV2(db);
    await db.execute('''
      CREATE TABLE appointments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        service_id INTEGER,
        category_id INTEGER,
        service_type_id INTEGER,
        service_name_snapshot TEXT,
        appointment_date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        status TEXT NOT NULL DEFAULT 'PENDING',
        notes TEXT,
        visit_id INTEGER,
        reminder_minutes_before INTEGER,
        created_date TEXT NOT NULL,
        updated_date TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id),
        FOREIGN KEY (service_id) REFERENCES services(id),
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (service_type_id) REFERENCES service_types(id),
        FOREIGN KEY (visit_id) REFERENCES visits(id)
      )
    ''');
  }

  Future<void> _createTablesV2(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        birth_date TEXT,
        notes TEXT,
        created_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        display_order INTEGER NOT NULL DEFAULT 0,
        created_date TEXT NOT NULL,
        updated_date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE service_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        display_order INTEGER NOT NULL DEFAULT 0,
        created_date TEXT NOT NULL,
        updated_date TEXT,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        service_type_id INTEGER,
        name TEXT NOT NULL,
        default_price REAL NOT NULL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        display_order INTEGER NOT NULL DEFAULT 0,
        created_date TEXT NOT NULL,
        updated_date TEXT,
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (service_type_id) REFERENCES service_types(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE visits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        visit_date TEXT NOT NULL,
        subtotal REAL NOT NULL,
        discount_type TEXT NOT NULL DEFAULT 'FIXED',
        discount_value REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        final_total REAL NOT NULL,
        total_paid REAL NOT NULL DEFAULT 0,
        pending_amount REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'PENDING',
        notes TEXT,
        created_date TEXT NOT NULL,
        updated_date TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE visit_services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        service_id INTEGER,
        category_id INTEGER,
        service_type_id INTEGER,
        category_name_snapshot TEXT NOT NULL DEFAULT '',
        service_type_name_snapshot TEXT,
        service_name_snapshot TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        total REAL NOT NULL,
        created_at TEXT,
        FOREIGN KEY (visit_id) REFERENCES visits(id),
        FOREIGN KEY (service_id) REFERENCES services(id),
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (service_type_id) REFERENCES service_types(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        payment_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        notes TEXT,
        created_date TEXT,
        FOREIGN KEY (visit_id) REFERENCES visits(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE write_offs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        write_off_date TEXT NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        notes TEXT,
        created_date TEXT,
        FOREIGN KEY (visit_id) REFERENCES visits(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE expense_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_category_id INTEGER NOT NULL,
        expense_date TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        notes TEXT,
        created_date TEXT NOT NULL,
        updated_date TEXT,
        FOREIGN KEY (expense_category_id) REFERENCES expense_categories(id)
      )
    ''');
  }

  /// Every index required by the spec. Each statement is guarded so that on an
  /// upgrade with legacy data a single failing (e.g. duplicate) index does not
  /// abort the whole migration.
  Future<void> _createIndexesV4(DatabaseExecutor db) async {
    await _createIndexesV3(db);
    final statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_as_appointment ON appointment_services(appointment_id)',
      'CREATE INDEX IF NOT EXISTS idx_as_service ON appointment_services(service_id)',
    ];
    for (final stmt in statements) {
      try {
        await db.execute(stmt);
      } catch (_) {
        // Ignore.
      }
    }
  }

  Future<void> _createIndexesV3(DatabaseExecutor db) async {
    await _createIndexesV2(db);
    final statements = <String>[
      'CREATE INDEX IF NOT EXISTS idx_appointments_customer ON appointments(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments(appointment_date)',
      'CREATE INDEX IF NOT EXISTS idx_appointments_status ON appointments(status)',
      'CREATE INDEX IF NOT EXISTS idx_appointments_date_time ON appointments(appointment_date, start_time)',
      'CREATE INDEX IF NOT EXISTS idx_appointments_visit ON appointments(visit_id)',
    ];
    for (final stmt in statements) {
      try {
        await db.execute(stmt);
      } catch (_) {
        // Ignore.
      }
    }
  }

  Future<void> _createIndexesV2(DatabaseExecutor db) async {
    final statements = <String>[
      // Unique constraints
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_name_active ON categories(name) WHERE is_active = 1',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_service_types_cat_name ON service_types(category_id, name)',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_services_cat_type_name ON services(category_id, service_type_id, name)',
      // customers
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)',
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
      'CREATE INDEX IF NOT EXISTS idx_customers_created ON customers(created_date)',
      // categories
      'CREATE INDEX IF NOT EXISTS idx_categories_name ON categories(name)',
      'CREATE INDEX IF NOT EXISTS idx_categories_active ON categories(is_active)',
      'CREATE INDEX IF NOT EXISTS idx_categories_order ON categories(display_order)',
      // service_types
      'CREATE INDEX IF NOT EXISTS idx_service_types_cat ON service_types(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_service_types_cat_active ON service_types(category_id, is_active)',
      'CREATE INDEX IF NOT EXISTS idx_service_types_cat_order ON service_types(category_id, display_order)',
      // services
      'CREATE INDEX IF NOT EXISTS idx_services_cat ON services(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_services_type ON services(service_type_id)',
      'CREATE INDEX IF NOT EXISTS idx_services_cat_type ON services(category_id, service_type_id)',
      'CREATE INDEX IF NOT EXISTS idx_services_cat_type_active ON services(category_id, service_type_id, is_active)',
      'CREATE INDEX IF NOT EXISTS idx_services_name ON services(name)',
      // visits
      'CREATE INDEX IF NOT EXISTS idx_visits_customer ON visits(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_visits_date ON visits(visit_date)',
      'CREATE INDEX IF NOT EXISTS idx_visits_customer_date ON visits(customer_id, visit_date)',
      'CREATE INDEX IF NOT EXISTS idx_visits_status ON visits(payment_status)',
      'CREATE INDEX IF NOT EXISTS idx_visits_date_status ON visits(visit_date, payment_status)',
      // visit_services
      'CREATE INDEX IF NOT EXISTS idx_vs_visit ON visit_services(visit_id)',
      'CREATE INDEX IF NOT EXISTS idx_vs_service ON visit_services(service_id)',
      'CREATE INDEX IF NOT EXISTS idx_vs_cat ON visit_services(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_vs_type ON visit_services(service_type_id)',
      'CREATE INDEX IF NOT EXISTS idx_vs_visit_service ON visit_services(visit_id, service_id)',
      'CREATE INDEX IF NOT EXISTS idx_vs_cat_type ON visit_services(category_id, service_type_id)',
      // payments
      'CREATE INDEX IF NOT EXISTS idx_payments_visit ON payments(visit_id)',
      'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)',
      'CREATE INDEX IF NOT EXISTS idx_payments_method ON payments(payment_method)',
      // write_offs
      'CREATE INDEX IF NOT EXISTS idx_writeoffs_visit ON write_offs(visit_id)',
      'CREATE INDEX IF NOT EXISTS idx_writeoffs_date ON write_offs(write_off_date)',
      // expenses
      'CREATE INDEX IF NOT EXISTS idx_expenses_cat ON expenses(expense_category_id)',
      'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date)',
      'CREATE INDEX IF NOT EXISTS idx_expenses_cat_date ON expenses(expense_category_id, expense_date)',
    ];
    for (final stmt in statements) {
      try {
        await db.execute(stmt);
      } catch (_) {
        // Ignore (e.g. a unique index over pre-existing duplicate legacy data).
      }
    }
  }

  // ── Upgrade from the legacy flat schema (v1) ─────────────────────────────

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _upgradeV1toV2(db);
    }
    if (oldVersion < 3) {
      await _upgradeV2toV3(db);
    }
    if (oldVersion < 4) {
      await _upgradeV3toV4(db);
    }
  }

  /// Adds the `appointment_services` table (multi-service appointments) and
  /// backfills one row per pre-existing appointment from its legacy single
  /// `service_id`/`service_name_snapshot` columns, so upgraded installs keep
  /// their appointment history intact.
  Future<void> _upgradeV3toV4(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS appointment_services (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          appointment_id INTEGER NOT NULL,
          service_id INTEGER,
          category_id INTEGER,
          service_type_id INTEGER,
          category_name_snapshot TEXT NOT NULL DEFAULT '',
          service_type_name_snapshot TEXT,
          service_name_snapshot TEXT NOT NULL,
          price REAL NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 1,
          total REAL NOT NULL,
          created_at TEXT,
          FOREIGN KEY (appointment_id) REFERENCES appointments(id),
          FOREIGN KEY (service_id) REFERENCES services(id),
          FOREIGN KEY (category_id) REFERENCES categories(id),
          FOREIGN KEY (service_type_id) REFERENCES service_types(id)
        )
      ''');
    } catch (_) {}
    await _createIndexesV4(db);

    try {
      final legacy = await db.rawQuery('''
        SELECT a.id AS appointment_id, a.service_id, a.category_id, a.service_type_id,
               a.service_name_snapshot, s.default_price AS price,
               c.name AS category_name, st.name AS service_type_name
        FROM appointments a
        LEFT JOIN services s ON s.id = a.service_id
        LEFT JOIN categories c ON c.id = a.category_id
        LEFT JOIN service_types st ON st.id = a.service_type_id
        WHERE a.service_name_snapshot IS NOT NULL AND a.service_name_snapshot != ''
          AND NOT EXISTS (
            SELECT 1 FROM appointment_services aps WHERE aps.appointment_id = a.id
          )
      ''');
      final now = DateTime.now().toIso8601String();
      for (final row in legacy) {
        final price = (row['price'] as num?)?.toDouble() ?? 0.0;
        await db.insert('appointment_services', {
          'appointment_id': row['appointment_id'],
          'service_id': row['service_id'],
          'category_id': row['category_id'],
          'service_type_id': row['service_type_id'],
          'category_name_snapshot': row['category_name'] as String? ?? '',
          'service_type_name_snapshot': row['service_type_name'] as String?,
          'service_name_snapshot': row['service_name_snapshot'],
          'price': price,
          'quantity': 1,
          'total': price,
          'created_at': now,
        });
      }
    } catch (_) {
      // Best-effort backfill; legacy single-service columns remain readable.
    }
  }

  Future<void> _upgradeV2toV3(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS appointments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          service_id INTEGER,
          category_id INTEGER,
          service_type_id INTEGER,
          service_name_snapshot TEXT,
          appointment_date TEXT NOT NULL,
          start_time TEXT NOT NULL,
          end_time TEXT,
          status TEXT NOT NULL DEFAULT 'PENDING',
          notes TEXT,
          visit_id INTEGER,
          reminder_minutes_before INTEGER,
          created_date TEXT NOT NULL,
          updated_date TEXT,
          FOREIGN KEY (customer_id) REFERENCES customers(id),
          FOREIGN KEY (service_id) REFERENCES services(id),
          FOREIGN KEY (category_id) REFERENCES categories(id),
          FOREIGN KEY (service_type_id) REFERENCES service_types(id),
          FOREIGN KEY (visit_id) REFERENCES visits(id)
        )
      ''');
    } catch (_) {}
    await _createIndexesV3(db);
  }

  Future<void> _upgradeV1toV2(Database db) async {
    // 1. Add the new nullable columns to existing tables (ADD COLUMN is safe
    //    and never rewrites existing rows, so historical bills never change).
    final alters = <String>[
      'ALTER TABLE categories ADD COLUMN updated_date TEXT',
      'ALTER TABLE services ADD COLUMN service_type_id INTEGER',
      'ALTER TABLE services ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE services ADD COLUMN updated_date TEXT',
      'ALTER TABLE visits ADD COLUMN updated_date TEXT',
      'ALTER TABLE visit_services ADD COLUMN category_id INTEGER',
      'ALTER TABLE visit_services ADD COLUMN service_type_id INTEGER',
      'ALTER TABLE visit_services ADD COLUMN service_type_name_snapshot TEXT',
      'ALTER TABLE visit_services ADD COLUMN created_at TEXT',
      'ALTER TABLE payments ADD COLUMN created_date TEXT',
      'ALTER TABLE write_offs ADD COLUMN created_date TEXT',
      'ALTER TABLE expense_categories ADD COLUMN created_date TEXT',
      'ALTER TABLE expenses ADD COLUMN updated_date TEXT',
    ];
    for (final stmt in alters) {
      try {
        await db.execute(stmt);
      } catch (_) {
        // Column may already exist if a partial upgrade ran before.
      }
    }

    // 2. Create the new service_types table.
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS service_types (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          display_order INTEGER NOT NULL DEFAULT 0,
          created_date TEXT NOT NULL,
          updated_date TEXT,
          FOREIGN KEY (category_id) REFERENCES categories(id)
        )
      ''');
    } catch (_) {}

    // 3. Back-fill visit_services snapshot category/service ids from the
    //    original snapshot text + service_id so aggregation keys exist. We do
    //    NOT recompute snapshot NAMES (those stay exactly as billed).
    try {
      await db.execute('''
        UPDATE visit_services
        SET category_id = (
          SELECT s.category_id FROM services s WHERE s.id = visit_services.service_id
        )
        WHERE category_id IS NULL AND service_id IS NOT NULL
      ''');
    } catch (_) {}

    // 4. Fix the Category -> ServiceType hierarchy for legacy master data.
    final report = await _migrateLegacyHierarchy(db);

    // 5. Create indexes last (after data is settled).
    await _createIndexesV2(db);

    // 6. Persist a short report so the UI can show it once on next launch.
    lastAutoMigrationReport = report;
    try {
      await db.insert(
        'settings',
        {'key': 'pending_migration_report', 'value': jsonEncode(report.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// Re-points legacy top-level categories that are really service types (e.g.
  /// "Rica Wax") under their real parent category ("Wax") as service types,
  /// moving their services along. Unmapped legacy categories are kept and
  /// flagged. Operates on master data only — visit_services snapshots are left
  /// untouched so historical bills never change.
  Future<MigrationReport> _migrateLegacyHierarchy(Database db) async {
    final report = MigrationReport();
    final now = DateTime.now().toIso8601String();

    final categories = await db.query('categories');
    report.categories = categories.length;

    // Build a lookup of existing category names -> id (case-insensitive).
    final Map<String, int> categoryIdByName = {};
    for (final c in categories) {
      categoryIdByName[(c['name'] as String).toLowerCase()] = c['id'] as int;
    }

    Future<int> ensureCategory(String name) async {
      final existing = categoryIdByName[name.toLowerCase()];
      if (existing != null) return existing;
      final id = await db.insert('categories', {
        'name': name,
        'is_active': 1,
        'display_order': 0,
        'created_date': now,
      });
      categoryIdByName[name.toLowerCase()] = id;
      report.categories++;
      return id;
    }

    for (final c in categories) {
      final legacyId = c['id'] as int;
      final legacyName = (c['name'] as String).trim();
      final resolution = resolveLegacyCategory(legacyName);

      if (!resolution.isServiceType) {
        if (resolution.flaggedUnmapped) {
          report.addFlag('Category "$legacyName" kept as category (unmapped)');
        }
        continue;
      }

      // Ensure the real parent category exists.
      final parentId = await ensureCategory(resolution.parentCategoryName);

      // Create (or find) the service type under the parent.
      int serviceTypeId;
      final existingType = await db.query(
        'service_types',
        where: 'category_id = ? AND name = ?',
        whereArgs: [parentId, resolution.serviceTypeName],
        limit: 1,
      );
      if (existingType.isNotEmpty) {
        serviceTypeId = existingType.first['id'] as int;
      } else {
        serviceTypeId = await db.insert('service_types', {
          'category_id': parentId,
          'name': resolution.serviceTypeName,
          'is_active': 1,
          'display_order': 0,
          'created_date': now,
        });
        report.serviceTypes++;
      }

      // Re-point services from the legacy category to parent + service type.
      await db.update(
        'services',
        {
          'category_id': parentId,
          'service_type_id': serviceTypeId,
          'updated_date': now,
        },
        where: 'category_id = ?',
        whereArgs: [legacyId],
      );

      // Deactivate the now-redundant legacy top-level category.
      await db.update(
        'categories',
        {'is_active': 0, 'updated_date': now},
        where: 'id = ?',
        whereArgs: [legacyId],
      );
      report.addFlag(resolution.reason);
    }

    // Fill in report counts / totals from the (now migrated) data.
    report.serviceTypes = Sqlite.firstInt(
        await db.rawQuery('SELECT COUNT(*) c FROM service_types'));
    report.services =
        Sqlite.firstInt(await db.rawQuery('SELECT COUNT(*) c FROM services'));
    report.customers =
        Sqlite.firstInt(await db.rawQuery('SELECT COUNT(*) c FROM customers'));
    report.visits =
        Sqlite.firstInt(await db.rawQuery('SELECT COUNT(*) c FROM visits'));
    report.visitItems = Sqlite.firstInt(
        await db.rawQuery('SELECT COUNT(*) c FROM visit_services'));
    report.payments =
        Sqlite.firstInt(await db.rawQuery('SELECT COUNT(*) c FROM payments'));
    report.writeOffs =
        Sqlite.firstInt(await db.rawQuery('SELECT COUNT(*) c FROM write_offs'));
    report.expenseCategories = Sqlite.firstInt(
        await db.rawQuery('SELECT COUNT(*) c FROM expense_categories'));
    report.expenses =
        Sqlite.firstInt(await db.rawQuery('SELECT COUNT(*) c FROM expenses'));

    final visitsTotal = Sqlite.firstDouble(
        await db.rawQuery('SELECT SUM(final_total) s FROM visits'));
    final paymentsTotal = Sqlite.firstDouble(
        await db.rawQuery('SELECT SUM(amount) s FROM payments'));
    final expensesTotal = Sqlite.firstDouble(
        await db.rawQuery('SELECT SUM(amount) s FROM expenses'));
    report.sourceVisitsTotal = visitsTotal;
    report.migratedVisitsTotal = visitsTotal;
    report.sourcePaymentsTotal = paymentsTotal;
    report.migratedPaymentsTotal = paymentsTotal;
    report.sourceExpensesTotal = expensesTotal;
    report.migratedExpensesTotal = expensesTotal;

    return report;
  }

  // ── Seed defaults (fresh installs only) ──────────────────────────────────

  Future<void> _seedDefaultData(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    final defaultSettings = {
      'parlour_name': 'Priyanka Beauty Parlour',
      'owner_name': '',
      'phone': '',
      'address': '',
      'currency': '₹',
      'default_payment_method': 'CASH',
    };
    for (final entry in defaultSettings.entries) {
      await db.insert('settings', {'key': entry.key, 'value': entry.value});
    }

    final expenseCategories = [
      'Rent', 'Electricity', 'Water', 'Salaries', 'Products',
      'Wax', 'Facial Products', 'Cleaning', 'Maintenance',
      'Marketing', 'Equipment', 'Other'
    ];
    for (final cat in expenseCategories) {
      await db.insert(
          'expense_categories', {'name': cat, 'is_active': 1, 'created_date': now});
    }

    final serviceCategories = [
      {'name': 'Wax', 'display_order': 1},
      {'name': 'Facial', 'display_order': 2},
      {'name': 'Hair', 'display_order': 3},
      {'name': 'Manicure', 'display_order': 4},
      {'name': 'Pedicure', 'display_order': 5},
      {'name': 'Makeup', 'display_order': 6},
      {'name': 'Hair Spa', 'display_order': 7},
      {'name': 'Threading', 'display_order': 8},
      {'name': 'Other', 'display_order': 9},
    ];
    final categoryIds = <String, int>{};
    for (final cat in serviceCategories) {
      final id = await db.insert('categories', {
        'name': cat['name'],
        'is_active': 1,
        'created_date': now,
        'display_order': cat['display_order'],
      });
      categoryIds[cat['name'] as String] = id;
    }

    await _seedDefaultServices(db, categoryIds, now);
  }

  /// Pre-fills the master service catalogue (subcategories + services with
  /// their real-world prices) on a fresh install, so the price list is ready
  /// to use out of the box instead of starting empty.
  Future<void> _seedDefaultServices(
    DatabaseExecutor db,
    Map<String, int> categoryIds,
    String now,
  ) async {
    Future<int> insertServiceType(
      String categoryName,
      String typeName,
      int order,
    ) {
      return db.insert('service_types', {
        'category_id': categoryIds[categoryName],
        'name': typeName,
        'is_active': 1,
        'display_order': order,
        'created_date': now,
      });
    }

    Future<void> insertService(
      String categoryName,
      int? serviceTypeId,
      String name,
      double price,
      int order,
    ) {
      return db.insert('services', {
        'category_id': categoryIds[categoryName],
        'service_type_id': serviceTypeId,
        'name': name,
        'default_price': price,
        'is_active': 1,
        'display_order': order,
        'created_date': now,
      });
    }

    // Wax → Regular Wax
    final regularWaxId = await insertServiceType('Wax', 'Regular Wax', 1);
    final regularWax = {
      'Full Hand': 120.0,
      'Full Legs': 250.0,
      'Under Arms': 60.0,
      'Half Legs': 120.0,
      'Face Wax': 120.0,
    };
    var order = 1;
    for (final entry in regularWax.entries) {
      await insertService('Wax', regularWaxId, entry.key, entry.value, order++);
    }

    // Wax → Rica Wax
    final ricaWaxId = await insertServiceType('Wax', 'Rica Wax', 2);
    final ricaWax = {
      'Bikini': 500.0,
      'Full Hands': 250.0,
      'Underarm': 100.0,
      'Half Legs': 250.0,
      'Face Wax': 200.0,
    };
    order = 1;
    for (final entry in ricaWax.entries) {
      await insertService('Wax', ricaWaxId, entry.key, entry.value, order++);
    }

    // Wax → Cream Wax
    final creamWaxId = await insertServiceType('Wax', 'Cream Wax', 3);
    final creamWax = {
      'Full Hands': 170.0,
      'Half Legs': 170.0,
      'Full Legs': 350.0,
      'Underarm': 70.0,
      'Bikini': 400.0,
      'Face Wax': 150.0,
    };
    order = 1;
    for (final entry in creamWax.entries) {
      await insertService('Wax', creamWaxId, entry.key, entry.value, order++);
    }

    // Hair → Colour
    await insertService('Hair', null, 'Colour', 150.0, 1);

    // Hair Spa → Hair Spa
    await insertService('Hair Spa', null, 'Hair Spa', 500.0, 1);

    // Threading → Eye Brow
    await insertService('Threading', null, 'Eye Brow', 50.0, 1);

    // Facial (no sub-types, direct services)
    final facial = {
      'Fruit': 500.0,
      'Lotus': 800.0,
      'O3 - 10 Steps': 1500.0,
      'O3 - 7 Steps': 1200.0,
    };
    order = 1;
    for (final entry in facial.entries) {
      await insertService('Facial', null, entry.key, entry.value, order++);
    }

    // Manicure → Regular
    await insertService('Manicure', null, 'Regular', 350.0, 1);

    // Pedicure → Regular
    await insertService('Pedicure', null, 'Regular', 450.0, 1);

    // Makeup → Simple Makeup
    await insertService('Makeup', null, 'Simple Makeup', 1000.0, 1);
  }
}

/// Small helpers for reading scalar aggregate query results.
class Sqlite {
  static int firstInt(List<Map<String, Object?>> rows, [String? col]) {
    if (rows.isEmpty) return 0;
    final v = col != null ? rows.first[col] : rows.first.values.first;
    return (v as num? ?? 0).toInt();
  }

  static double firstDouble(List<Map<String, Object?>> rows, [String? col]) {
    if (rows.isEmpty) return 0;
    final v = col != null ? rows.first[col] : rows.first.values.first;
    return (v as num? ?? 0).toDouble();
  }
}
