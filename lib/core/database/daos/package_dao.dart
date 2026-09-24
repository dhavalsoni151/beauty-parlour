import 'package:sqflite/sqflite.dart';
import '../app_database.dart';
import '../../models/package_models.dart';
import 'db_exceptions.dart';

class PackageDao {
  Future<List<Package>> getAll({bool activeOnly = false}) async {
    final db = await AppDatabase.instance.database;
    final where = activeOnly ? 'WHERE is_active = 1' : '';
    final rows = await db.rawQuery('''
      SELECT * FROM packages
      $where
      ORDER BY is_active DESC, start_date DESC, name ASC
    ''');
    final packages = rows.map((r) => Package.fromMap(r)).toList();
    for (final p in packages) {
      p.services = await getPackageServices(p.id!);
    }
    return packages;
  }

  /// Packages valid (active + within date range) for [date] (yyyy-MM-dd or
  /// any ISO string — only the first 10 chars, the date portion, are used).
  Future<List<Package>> getValidForDate(String date) async {
    final d = date.length >= 10 ? date.substring(0, 10) : date;
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT * FROM packages
      WHERE is_active = 1 AND start_date <= ? AND expiry_date >= ?
      ORDER BY name ASC
    ''', [d, d]);
    final packages = rows.map((r) => Package.fromMap(r)).toList();
    for (final p in packages) {
      p.services = await getPackageServices(p.id!);
    }
    return packages;
  }

  Future<Package?> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('packages', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final package = Package.fromMap(rows.first);
    package.services = await getPackageServices(id);
    return package;
  }

  Future<List<PackageService>> getPackageServices(int packageId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('package_services',
        where: 'package_id = ?', whereArgs: [packageId], orderBy: 'id ASC');
    return rows.map((r) => PackageService.fromMap(r)).toList();
  }

  Future<int> insert(Package package) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final id = await txn.insert('packages', package.toMap());
      final createdAt = DateTime.now().toIso8601String();
      for (final s in package.services) {
        final map = s.toMap()
          ..['package_id'] = id
          ..['created_date'] = s.createdDate ?? createdAt;
        await txn.insert('package_services', map);
      }
      return id;
    });
  }

  Future<void> update(Package package) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'packages',
        {...package.toMap(), 'updated_date': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [package.id],
      );
      await txn.delete('package_services',
          where: 'package_id = ?', whereArgs: [package.id]);
      final createdAt = DateTime.now().toIso8601String();
      for (final s in package.services) {
        final map = s.toMap()
          ..['package_id'] = package.id
          ..['created_date'] = s.createdDate ?? createdAt;
        await txn.insert('package_services', map);
      }
    });
  }

  Future<void> toggleActive(int id, bool isActive) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'packages',
      {'is_active': isActive ? 1 : 0, 'updated_date': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a package, but only if it was never sold in a visit/appointment
  /// (historical transactions must never lose their package reference).
  Future<void> delete(int id) async {
    final db = await AppDatabase.instance.database;
    final visitCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM visits WHERE package_id = ?', [id])) ??
        0;
    final apptCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM appointments WHERE package_id = ?', [id])) ??
        0;
    if (visitCount > 0 || apptCount > 0) {
      throw const InUseException(
          'This package cannot be deleted because it has past visits or '
          'appointments linked to it. Deactivate it instead.');
    }
    await db.transaction((txn) async {
      await txn.delete('package_services', where: 'package_id = ?', whereArgs: [id]);
      await txn.delete('packages', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Re-validates a package for use on [date] (yyyy-MM-dd or ISO string).
  /// Called both when a package is selected AND again right before an
  /// appointment/visit that uses it is actually processed, since the
  /// package (or the appointment date) may have changed in between.
  Future<PackageValidationResult> validate(int packageId, String date) async {
    final package = await get(packageId);
    if (package == null) {
      return PackageValidationResult.fail('This package no longer exists.');
    }
    if (!package.isActive) {
      return PackageValidationResult.fail(
          'The "${package.name}" package is inactive and cannot be used.');
    }
    if (package.services.isEmpty) {
      return PackageValidationResult.fail(
          'The "${package.name}" package has no services configured.');
    }
    final d = date.length >= 10 ? date.substring(0, 10) : date;
    if (d.compareTo(package.startDate) < 0) {
      return PackageValidationResult.fail(
          'This package is not valid for the selected date. Package '
          'validity starts from ${package.startDate}.');
    }
    if (d.compareTo(package.expiryDate) > 0) {
      return PackageValidationResult.fail(
          'This package is not valid for the selected date. Package '
          'validity is from ${package.startDate} to ${package.expiryDate}.');
    }
    return PackageValidationResult.ok(package);
  }

  // ── Reports ───────────────────────────────────────────────────────────────

  /// Package sales summary: usage count, normal value, revenue and discount
  /// per package, aggregated from the historical snapshot columns on
  /// `visits` (never from the live `packages` table, so edits to a package's
  /// price never change past figures).
  Future<List<Map<String, dynamic>>> getPackageSalesReport({
    String? startDate,
    String? endDate,
  }) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>['v.package_id IS NOT NULL'];
    final args = <dynamic>[];
    if (startDate != null) {
      wheres.add('v.visit_date >= ?');
      args.add(startDate);
    }
    if (endDate != null) {
      wheres.add('v.visit_date < ?');
      args.add(endDate);
    }
    final rows = await db.rawQuery('''
      SELECT
        v.package_id AS package_id,
        v.package_name_snapshot AS package_name,
        COUNT(*) AS times_used,
        COALESCE(SUM(v.package_normal_total), 0) AS normal_value,
        COALESCE(SUM(v.package_price), 0) AS revenue,
        COALESCE(SUM(v.package_discount), 0) AS discount
      FROM visits v
      WHERE ${wheres.join(' AND ')}
      GROUP BY v.package_id, v.package_name_snapshot
      ORDER BY revenue DESC
    ''', args);
    return rows;
  }

  /// Which customers used a given package (or all packages if [packageId]
  /// is null), for the "Package Usage Report".
  Future<List<Map<String, dynamic>>> getPackageUsageReport({int? packageId}) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>['v.package_id IS NOT NULL'];
    final args = <dynamic>[];
    if (packageId != null) {
      wheres.add('v.package_id = ?');
      args.add(packageId);
    }
    final rows = await db.rawQuery('''
      SELECT v.id AS visit_id, v.package_name_snapshot AS package_name,
             v.visit_date, v.package_price AS amount, v.package_discount AS discount,
             c.name AS customer_name, c.id AS customer_id
      FROM visits v
      JOIN customers c ON c.id = v.customer_id
      WHERE ${wheres.join(' AND ')}
      ORDER BY v.visit_date DESC
    ''', args);
    return rows;
  }

  /// Total normal value vs. package revenue vs. discount across all package
  /// sales in a date range, for the "Package Discount Report".
  Future<Map<String, dynamic>> getPackageDiscountSummary({
    String? startDate,
    String? endDate,
  }) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>['package_id IS NOT NULL'];
    final args = <dynamic>[];
    if (startDate != null) {
      wheres.add('visit_date >= ?');
      args.add(startDate);
    }
    if (endDate != null) {
      wheres.add('visit_date < ?');
      args.add(endDate);
    }
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(package_normal_total), 0) AS normal_value,
        COALESCE(SUM(package_price), 0) AS revenue,
        COALESCE(SUM(package_discount), 0) AS discount
      FROM visits
      WHERE ${wheres.join(' AND ')}
    ''', args);
    return rows.first;
  }

  /// Buckets every package into active/upcoming/expiring-soon/expired for the
  /// "Package Expiry Report", relative to [today] (yyyy-MM-dd) and a
  /// [expiringWithinDays] window for "expiring soon".
  Future<Map<String, List<Package>>> getExpiryReport(
    String today, {
    int expiringWithinDays = 7,
  }) async {
    final all = await getAll();
    final soon = DateTime.parse(today)
        .add(Duration(days: expiringWithinDays))
        .toIso8601String()
        .substring(0, 10);
    final active = <Package>[];
    final upcoming = <Package>[];
    final expiringSoon = <Package>[];
    final expired = <Package>[];
    for (final p in all) {
      if (p.expiryDate.compareTo(today) < 0) {
        expired.add(p);
      } else if (p.startDate.compareTo(today) > 0) {
        upcoming.add(p);
      } else if (p.expiryDate.compareTo(soon) <= 0) {
        expiringSoon.add(p);
      } else {
        active.add(p);
      }
    }
    return {
      'active': active,
      'upcoming': upcoming,
      'expiringSoon': expiringSoon,
      'expired': expired,
    };
  }

  /// Dashboard KPIs: packages sold/revenue/discount in a date range, plus
  /// current active-package and expiring-soon counts.
  Future<Map<String, dynamic>> getDashboardStats(
    String startDate,
    String endDate,
  ) async {
    final db = await AppDatabase.instance.database;
    final salesRows = await db.rawQuery('''
      SELECT
        COUNT(*) AS packages_sold,
        COALESCE(SUM(package_price), 0) AS package_revenue,
        COALESCE(SUM(package_discount), 0) AS package_discount
      FROM visits
      WHERE package_id IS NOT NULL AND visit_date >= ? AND visit_date < ?
    ''', [startDate, endDate]);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final soon = DateTime.now()
        .add(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10);
    final activeCount = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM packages
      WHERE is_active = 1 AND start_date <= ? AND expiry_date >= ?
    ''', [today, today])) ?? 0;
    final expiringSoonCount = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM packages
      WHERE is_active = 1 AND start_date <= ? AND expiry_date >= ? AND expiry_date <= ?
    ''', [today, today, soon])) ?? 0;
    final row = salesRows.first;
    return {
      'packages_sold': (row['packages_sold'] as num? ?? 0).toInt(),
      'package_revenue': (row['package_revenue'] as num? ?? 0).toDouble(),
      'package_discount': (row['package_discount'] as num? ?? 0).toDouble(),
      'active_packages': activeCount,
      'packages_expiring_soon': expiringSoonCount,
    };
  }
}
