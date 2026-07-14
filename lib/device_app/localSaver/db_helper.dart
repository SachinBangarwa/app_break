import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:flutter/foundation.dart';

class AppDbHelper {
  static final AppDbHelper instance = AppDbHelper._init();
  static Database? _database;

  AppDbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('testproject_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path, 
      version: 1, 
      onCreate: _createDB,
      onOpen: _onOpen,
    );
  }

  Future _onOpen(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        packageName TEXT,
        title TEXT,
        body TEXT,
        timestamp INTEGER
      )
    ''');

    // Dynamically add columns to installed_apps if they are missing
    try {
      final columns = await db.rawQuery('PRAGMA table_info(installed_apps)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();

      final newCols = {
        'countdown': 'INTEGER DEFAULT 0',
        'lastOpened': 'INTEGER DEFAULT 0',
        'todayLimit': 'INTEGER DEFAULT 0',
        'todayUsage': 'INTEGER DEFAULT 0',
      };

      for (var entry in newCols.entries) {
        if (!columnNames.contains(entry.key)) {
          await db.execute('ALTER TABLE installed_apps ADD COLUMN ${entry.key} ${entry.value}');
          print("[AppDbHelper] Added column ${entry.key} to installed_apps table.");
        }
      }
    } catch (e) {
      print("[AppDbHelper] Error adding missing columns: $e");
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE installed_apps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        packageName TEXT UNIQUE,
        displayName TEXT,
        icon BLOB,
        isSystemApp INTEGER,
        isFavorite INTEGER DEFAULT 0,
        countdown INTEGER DEFAULT 0,
        lastOpened INTEGER DEFAULT 0,
        todayLimit INTEGER DEFAULT 0,
        todayUsage INTEGER DEFAULT 0
      )
    ''');
  }

  /// Syncs system apps with our SQLite database using a fast diff-check.
  /// Fetches apps list without icons first to check for changes.
  Future<bool> syncAppsWithSystem() async {
    final db = await database;

    // 1. Fetch package names and names from system (WITHOUT icons - extremely fast!)
    final List<AppInfo> systemAppsFast = await InstalledApps.getInstalledApps(
      excludeSystemApps: false,
      withIcon: false,
    );

    // 2. Fetch packageName, displayName, and isFavorite of all cached apps from SQLite
    final List<Map<String, dynamic>> cached = await db.query(
      'installed_apps',
      columns: ['packageName', 'displayName', 'isFavorite'],
    );
    
    final cachedMap = {
      for (var r in cached)
        r['packageName'] as String: {
          'displayName': r['displayName'] as String,
          'isFavorite': r['isFavorite'] as int,
        }
    };

    // 3. Find uninstalled apps (present in database but not in system fast list)
    final List<String> uninstalled = [];
    final systemPackageNames = systemAppsFast.map((a) => a.packageName).toSet();
    for (var pkg in cachedMap.keys) {
      if (!systemPackageNames.contains(pkg)) {
        uninstalled.add(pkg);
      }
    }

    // 4. Find new apps to install or existing apps with changed names
    final List<AppInfo> newApps = [];
    final List<AppInfo> changedNameApps = [];

    for (var app in systemAppsFast) {
      final cachedApp = cachedMap[app.packageName];
      if (cachedApp == null) {
        newApps.add(app);
      } else if (cachedApp['displayName'] != app.name) {
        changedNameApps.add(app);
      }
    }

    // 5. Apply changes in a single transaction if any modification is needed
    final hasChanges = uninstalled.isNotEmpty || newApps.isNotEmpty || changedNameApps.isNotEmpty;
    if (hasChanges) {
      await db.transaction((txn) async {
        // Delete uninstalled apps
        for (var pkg in uninstalled) {
          await txn.delete(
            'installed_apps',
            where: 'packageName = ?',
            whereArgs: [pkg],
          );
        }

        // Update name for apps with modified names (preserve icon and isFavorite)
        for (var app in changedNameApps) {
          await txn.update(
            'installed_apps',
            {
              'displayName': app.name,
            },
            where: 'packageName = ?',
            whereArgs: [app.packageName],
          );
        }

        // Fetch complete app info (with icon) for ONLY the newly installed apps and insert them
        for (var app in newApps) {
          try {
            final AppInfo? detailedApp = await InstalledApps.getAppInfo(app.packageName);
            if (detailedApp != null) {
              final defaultFavorites = const [
                'com.android.chrome',
                'com.google.android.youtube',
                'com.whatsapp',
                'com.openai.chatgpt'
              ];
              final int isFav = defaultFavorites.contains(app.packageName) ? 1 : 0;

              await txn.insert(
                'installed_apps',
                {
                  'packageName': detailedApp.packageName,
                  'displayName': detailedApp.name,
                  'icon': detailedApp.icon,
                  'isSystemApp': detailedApp.isSystemApp ? 1 : 0,
                  'isFavorite': isFav,
                },
              );
            }
          } catch (e) {
            debugPrint("Error syncing newly installed app ${app.packageName}: $e");
          }
        }
      });
    }
    return hasChanges;
  }

  /// Reads apps from database, optionally filtering system apps.
  Future<List<AppInfo>> getApps({required bool excludeSystemApps}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps;

    if (excludeSystemApps) {
      maps = await db.query(
        'installed_apps',
        where: 'isSystemApp = 0',
        orderBy: 'displayName COLLATE NOCASE',
      );
    } else {
      maps = await db.query(
        'installed_apps',
        orderBy: 'displayName COLLATE NOCASE',
      );
    }

    return maps.map((row) {
      return AppInfo.create({
        'name': row['displayName'] ?? '',
        'package_name': row['packageName'] ?? '',
        'icon': row['icon'],
        'is_system_app': row['isSystemApp'] == 1,
      });
    }).toList();
  }

  /// Reads favorite apps (placed on desktop shortcuts).
  Future<List<AppInfo>> getFavoriteApps() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'installed_apps',
      where: 'isFavorite = 1',
      orderBy: 'displayName COLLATE NOCASE',
    );

    return maps.map((row) {
      return AppInfo.create({
        'name': row['displayName'] ?? '',
        'package_name': row['packageName'] ?? '',
        'icon': row['icon'],
        'is_system_app': row['isSystemApp'] == 1,
      });
    }).toList();
  }

  /// Updates favorite status of an app.
  Future<void> updateFavoriteStatus(String packageName, bool isFav) async {
    final db = await database;
    await db.update(
      'installed_apps',
      {'isFavorite': isFav ? 1 : 0},
      where: 'packageName = ?',
      whereArgs: [packageName],
    );
  }

  /// Checks if an app is favorite.
  Future<bool> isAppFavorite(String packageName) async {
    final db = await database;
    final maps = await db.query(
      'installed_apps',
      columns: ['isFavorite'],
      where: 'packageName = ?',
      whereArgs: [packageName],
    );
    if (maps.isEmpty) return false;
    return maps.first['isFavorite'] == 1;
  }

  /// Inserts a single newly installed app into SQLite database.
  Future<AppInfo?> addSingleApp(String packageName) async {
    try {
      final db = await database;
      final AppInfo? detailedApp = await InstalledApps.getAppInfo(packageName);
      if (detailedApp != null) {
        final defaultFavorites = const [
          'com.android.chrome',
          'com.google.android.youtube',
          'com.whatsapp',
          'com.openai.chatgpt'
        ];
        final int isFav = defaultFavorites.contains(packageName) ? 1 : 0;

        await db.insert(
          'installed_apps',
          {
            'packageName': detailedApp.packageName,
            'displayName': detailedApp.name,
            'icon': detailedApp.icon,
            'isSystemApp': detailedApp.isSystemApp ? 1 : 0,
            'isFavorite': isFav,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return detailedApp;
      }
    } catch (e) {
      debugPrint("Error inserting single app $packageName: $e");
    }
    return null;
  }

  /// Deletes a single uninstalled app from SQLite database.
  Future<void> removeSingleApp(String packageName) async {
    try {
      final db = await database;
      await db.delete(
        'installed_apps',
        where: 'packageName = ?',
        whereArgs: [packageName],
      );
    } catch (e) {
      debugPrint("Error deleting single app $packageName: $e");
    }
  }

  /// Fetches all saved notifications from SQLite database (newest first).
  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final db = await database;
      return await db.query(
        'notifications',
        orderBy: 'timestamp DESC',
      );
    } catch (e) {
      debugPrint("Error fetching notifications: $e");
      return [];
    }
  }

  /// Clears all saved notifications from SQLite database.
  Future<void> clearAllNotifications() async {
    try {
      final db = await database;
      await db.delete('notifications');
    } catch (e) {
      debugPrint("Error clearing notifications: $e");
    }
  }
}
