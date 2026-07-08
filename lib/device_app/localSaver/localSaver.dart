// ignore_for_file: file_names
import 'package:shared_preferences/shared_preferences.dart';

/// Same pattern as LocalDataSaver — all SharedPreferences reads/writes for
/// the app-usage-limit feature live here, behind named methods, instead of
/// raw prefs.getInt('some_key_$pkg') calls scattered across the service.
class UsageDataSaver {
  // ---------------------------------------------------------------------
  // Fixed (non package-specific) keys
  // ---------------------------------------------------------------------
  static String lastPollTime = 'last_poll_time';
  static String lastResetDay = 'last_reset_day';
  static String openApp = 'open_app';
  static String openAppStart = 'open_app_start';
  static String activeBlockedPackage = 'active_blocked_package';
  static String activeBlockedName = 'active_blocked_name';
  static String notificationSaverEnabled = 'is_notification_saver_enabled';

  // ---------------------------------------------------------------------
  // Per-package key prefixes (actual key = prefix + packageName)
  // ---------------------------------------------------------------------
  static String usagePrefix = 'usage_';
  static String committedUsagePrefix = 'committed_usage_';
  static String limitPrefix = 'limit_';
  static String snoozeUntilPrefix = 'snooze_until_';
  static String namePrefix = 'name_';
  static String timeLeftPrefix = 'time_left_';

  // =======================================================================
  // last_poll_time
  // =======================================================================
  static Future<bool> saveLastPollTime(int millis) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setInt(lastPollTime, millis);
  }

  static Future<int?> getLastPollTime() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getInt(lastPollTime);
  }

  static Future<bool> hasLastPollTime() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.containsKey(lastPollTime);
  }

  // =======================================================================
  // last_reset_day
  // =======================================================================
  static Future<bool> saveLastResetDay(String day) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setString(lastResetDay, day);
  }

  static Future<String?> getLastResetDay() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString(lastResetDay);
  }

  // =======================================================================
  // open_app / open_app_start  (currently-foreground app + its start time)
  // =======================================================================
  static Future<bool> saveOpenApp(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setString(openApp, packageName);
  }

  static Future<String?> getOpenApp() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString(openApp);
  }

  static Future<bool> saveOpenAppStart(int millis) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setInt(openAppStart, millis);
  }

  static Future<int?> getOpenAppStart() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getInt(openAppStart);
  }

  // =======================================================================
  // active_blocked_package / active_blocked_name
  // =======================================================================
  static Future<bool> saveActiveBlockedPackage(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setString(activeBlockedPackage, packageName);
  }

  static Future<String?> getActiveBlockedPackage() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString(activeBlockedPackage);
  }

  static Future<bool> saveActiveBlockedName(String name) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setString(activeBlockedName, name);
  }

  static Future<String?> getActiveBlockedName() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString(activeBlockedName);
  }

  // =======================================================================
  // committed_usage_<package>  (authoritative, only moves at session close)
  // =======================================================================
  static Future<bool> saveCommittedUsage(String packageName, int millis) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setInt('$committedUsagePrefix$packageName', millis);
  }

  static Future<int> getCommittedUsage(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getInt('$committedUsagePrefix$packageName') ?? 0;
  }

  /// Adds durationMillis on top of whatever is already committed for this
  /// package, and saves it back. Used every time a session actually ends.
  static Future<void> addCommittedUsage(String packageName, int durationMillis) async {
    final prev = await getCommittedUsage(packageName);
    await saveCommittedUsage(packageName, prev + durationMillis);
  }

  // =======================================================================
  // usage_<package>  (live-updating "today total" — for UI display)
  // =======================================================================
  static Future<bool> saveUsage(String packageName, int millis) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setInt('$usagePrefix$packageName', millis);
  }

  static Future<int> getUsage(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getInt('$usagePrefix$packageName') ?? 0;
  }

  // =======================================================================
  // limit_<package>  (user-configured daily limit, in ms)
  // =======================================================================
  static Future<bool> saveLimit(String packageName, int millis) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setInt('$limitPrefix$packageName', millis);
  }

  static Future<int> getLimit(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getInt('$limitPrefix$packageName') ?? 0;
  }

  // =======================================================================
  // snooze_until_<package>  ("+2 Minutes" button on the overlay)
  // =======================================================================
  static Future<bool> saveSnoozeUntil(String packageName, int millis) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setInt('$snoozeUntilPrefix$packageName', millis);
  }

  static Future<int> getSnoozeUntil(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getInt('$snoozeUntilPrefix$packageName') ?? 0;
  }

  // =======================================================================
  // name_<package>  (display name shown on the overlay)
  // =======================================================================
  static Future<bool> saveAppName(String packageName, String name) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setString('$namePrefix$packageName', name);
  }

  static Future<String> getAppName(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString('$namePrefix$packageName') ?? packageName;
  }

  // =======================================================================
  // limit config & time left helpers
  // =======================================================================
  static Future<void> saveLimitConfig(String packageName, String appName, int limitMs, int timeLeftMs) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString('$namePrefix$packageName', appName);
    await preferences.setInt('$limitPrefix$packageName', limitMs);
    await preferences.setInt('$timeLeftPrefix$packageName', timeLeftMs);
  }

  static Future<int> getTimeLeft(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    final limit = preferences.getInt('$limitPrefix$packageName') ?? 0;
    return preferences.getInt('$timeLeftPrefix$packageName') ?? limit;
  }

  static Future<bool> saveTimeLeft(String packageName, int timeLeftMs) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return await preferences.setInt('$timeLeftPrefix$packageName', timeLeftMs);
  }

  // =======================================================================
  // Force-reload prefs from disk (call once at the start of a poll cycle,
  // same as `prefs.reload()` before).
  // =======================================================================
  static Future<void> reload() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.reload();
  }

  // =======================================================================
  // Wipe all usage_*/committed_usage_*/time_left_* keys — called on day rollover.
  // =======================================================================
  static Future<void> resetAllUsageForNewDay() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    final allKeys = preferences.getKeys();
    for (final k in allKeys) {
      if (k.startsWith(usagePrefix) ||
          k.startsWith(committedUsagePrefix) ||
          k.startsWith(timeLeftPrefix)) {
        await preferences.remove(k);
      }
    }
    await preferences.remove(openApp);
  }

  /// Clears all keys for a specific package when uninstalled.
  static Future<void> clearLimitConfig(String packageName) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove('$namePrefix$packageName');
    await preferences.remove('$limitPrefix$packageName');
    await preferences.remove('$timeLeftPrefix$packageName');
    await preferences.remove('$usagePrefix$packageName');
    await preferences.remove('$committedUsagePrefix$packageName');
    await preferences.remove('$snoozeUntilPrefix$packageName');
  }

  /// Sets whether the notification saver is enabled or disabled.
  static Future<bool> saveNotificationSaverEnabled(bool enabled) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    // Use the flutter. prefix implicitly handled by SharedPreferences package
    return await preferences.setBool(notificationSaverEnabled, enabled);
  }

  /// Checks if the notification saver is enabled (default: true).
  static Future<bool> isNotificationSaverEnabled() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(notificationSaverEnabled) ?? true;
  }
}