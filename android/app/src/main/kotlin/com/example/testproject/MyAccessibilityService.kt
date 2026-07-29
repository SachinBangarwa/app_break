package com.example.testproject

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin
import org.json.JSONObject

/**
 * MyAccessibilityService:
 * Yeh class Android Accessibility Service hai jo screen state changes ko observe karti hai.
 * Jab ye active hoti hai, toh bina kisi background Dart service ke, ye completely native Kotlin me
 * limits check aur overlays window draw karti hai.
 */
class MyAccessibilityService : AccessibilityService() {

    private var screenReceiver: BroadcastReceiver? = null
    private lateinit var dbHelper: AppDbHelper
    private val handler = Handler(Looper.getMainLooper())

    // Currently tracked app details in memory
    private var openApp: String? = null
    private var openAppStart: Long = 0

    // Timer runnables for daily limit and session prompt
    private val blockRunnable = Runnable { checkAndTriggerOverlay(true) }
    private val promptRunnable = Runnable { checkAndTriggerOverlay(false) }

    override fun onCreate() {
        super.onCreate()
        dbHelper = AppDbHelper(this) // SQLite helper ko initialize karenge

        // Screen Off hone par active session ka time database me save karne ke liye receiver
        try {
            screenReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                        // Screen off hone par session close (package = empty)
                        handlePackageChanged("")
                    }
                }
            }
            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
            registerReceiver(screenReceiver, filter)
        } catch (e: Exception) {
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_accessibility_enabled", true).apply()

            // Default home launcher package detect karke prefs me save karenge
            try {
                val intent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                }
                val resolveInfo = packageManager.resolveActivity(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                val launcherPackage = resolveInfo?.activityInfo?.packageName
                if (launcherPackage != null && launcherPackage.isNotEmpty()) {
                    prefs.edit().putString("flutter.default_launcher_package", launcherPackage).apply()
                }
            } catch (ex: Exception) {
            }

            // SQLite database se active limits loaded apps ko load karenge
            reloadActiveAppsList()

            // Safe check for flutter.reminder_option (Flutter saves integers as Long, causing ClassCastException with getInt)
            val reminderVal = prefs.all["flutter.reminder_option"]
            val reminderOpt = when (reminderVal) {
                is Int -> reminderVal
                is Long -> reminderVal.toInt()
                is Float -> reminderVal.toInt()
                is Double -> reminderVal.toInt()
                is String -> reminderVal.toIntOrNull() ?: 0
                else -> 0 // Default to 0 (Always Ask) to match Flutter default fallback
            }
            ActiveAppsManager.reminderOptionSetting = reminderOpt

            notifyAccessibilityStatusChanged(true)
        } catch (e: Exception) {
        }
    }

    // Window configuration change hone par call hota hai (e.g. app switch)
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val pkg = event.packageName?.toString() ?: ""
        val eventTypeName = AccessibilityEvent.eventTypeToString(event.eventType)
        val isOverlayActive = NativeOverlayManager.isOverlayShowing()

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || 
            event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            Log.d("FocusDebug", "[ManagerLog] Accessibility Event -> Type: $eventTypeName | Package: '$pkg' | Class: '${event.className}' | Overlay Active? => $isOverlayActive")
        }

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            handlePackageChanged(pkg)
        }
    }

    /**
     * handlePackageChanged:
     * App switch hone par calculations aur state transitions perform karta hai.
     * (Pichhle app ka timing commit karna, naye app ki limits check karna).
     */
    private fun handlePackageChanged(packageName: String) {
        if (NativeOverlayManager.activeOverlayPackage == packageName) {
            return
        }
        val now = System.currentTimeMillis()
        val prevApp = openApp
        val prevStart = openAppStart

        // 0. Agar user same app par hi kaam kar raha hai (window event same app ka hai)
        if (prevApp == packageName) {
            if (packageName.isNotEmpty() && !isIgnoredPackage(packageName)) {
                val duration = now - prevStart
                if (duration > 0) {
                    reloadActiveAppsList()
                    val app = ActiveAppsManager.activeAppsList.find { it.packageName == packageName }
                    if (app != null) {
                        app.todayUsage += duration
                        dbHelper.updateAppUsage(packageName, app.todayUsage)
                        openAppStart = now // reset start time to now
                        checkLimitsAndSchedule(packageName, app)
                    }
                }
            }
            return
        }

        // 1. Pichhle app ka session calculate aur SQLite me save karenge
        if (prevApp != null && prevApp.isNotEmpty() && prevApp != packageName) {
            // TRANSITION ARTIFACT FILTER:
            // Agar pichhla app tracked tha aur naya focus event humare khud ke app (com.example.testproject) ka hai
            // aur ye switch 1.5 seconds (1500ms) se kam me hua hai, toh ye system transition noise hai.
            // Hum ise ignore karenge taaki user ki live tracking timer cancel na ho.
            if (packageName == "com.example.testproject" && (now - prevStart) < 1500) {
                return
            }

            val duration = now - prevStart
            if (duration > 0) {
                val app = ActiveAppsManager.activeAppsList.find { it.packageName == prevApp }
                if (app != null) {
                    app.todayUsage += duration
                    dbHelper.updateAppUsage(prevApp, app.todayUsage)
                }
            }
            // Clear session mapping if in "Always Show" mode so it prompts again on next open
            if (ActiveAppsManager.reminderOptionSetting == -1) {
                ActiveAppsManager.sessionStartTimeMap.remove(prevApp)
                ActiveAppsManager.sessionLimitMap.remove(prevApp)
            }
            // Purane delay check callbacks ko cancel karenge
            handler.removeCallbacks(blockRunnable)
            handler.removeCallbacks(promptRunnable)
            openApp = null
            openAppStart = 0
        }

        // 2. Naye app ke liye limit checks aur scheduling chalenge
        if (packageName.isNotEmpty() && !isIgnoredPackage(packageName)) {
            // Check Focus mode blocking directly in accessibility service
            if (checkFocusModeAndShowOverlay(packageName)) {
                return
            }

            // DB se update active app list read karenge (taaki Flutter UI ke changes refresh ho sakein)
            reloadActiveAppsList()

            val trackedApp = ActiveAppsManager.activeAppsList.find { it.packageName == packageName }
            if (trackedApp != null) {
                openApp = packageName
                openAppStart = now
                
                // Timers aur checking trigger karenge
                checkLimitsAndSchedule(packageName, trackedApp)
            }
        }
    }

    /**
     * checkLimitsAndSchedule:
     * Naye app ke daily limits, presets aur custom session checks runs karta hai.
     */
    private fun checkLimitsAndSchedule(packageName: String, app: CustomAppModel) {
        val now = System.currentTimeMillis()
        val allowedLimit = app.todayLimit + app.extraLimit
        val todayUsage = app.todayUsage


        // A. Daily Limit Block Check
        if (app.todayLimit > 0 && todayUsage >= allowedLimit) {
            NativeOverlayManager.showBlockOverlay(this, packageName, (todayUsage / 60000).toInt()) {
                openApp = null
                openAppStart = 0
                handler.removeCallbacks(blockRunnable)
                handler.removeCallbacks(promptRunnable)
                goHome()
            }
            return
        }

        // B. Session limit check logic (Auto vs Custom)
        val reminderOpt = ActiveAppsManager.reminderOptionSetting
        var isSessionPromptNeeded = false
        var sessionRemainingMs = Long.MAX_VALUE

        if (reminderOpt == -1) {
            // Always Show mode: check if session is already active (meaning bypassed)
            val sessionStart = ActiveAppsManager.sessionStartTimeMap[packageName] ?: 0L
            if (sessionStart <= 0L) {
                isSessionPromptNeeded = true
            } else {
                isSessionPromptNeeded = false
                sessionRemainingMs = Long.MAX_VALUE
            }
        } else if (reminderOpt > 0) {
            // Auto preset limit set hai
            val preSetMs = reminderOpt * 60000L
            var sessionStart = ActiveAppsManager.sessionStartTimeMap[packageName] ?: 0L
            if (sessionStart <= 0L) {
                ActiveAppsManager.sessionLimitMap[packageName] = preSetMs
                ActiveAppsManager.sessionStartTimeMap[packageName] = now
                sessionStart = now
            }
            val elapsedSession = now - sessionStart
            if (elapsedSession >= preSetMs) {
                isSessionPromptNeeded = true
            } else {
                sessionRemainingMs = preSetMs - elapsedSession
            }
        } else {
            // Custom session time limit set hai
            val sessionLimit = ActiveAppsManager.sessionLimitMap[packageName] ?: 0L
            val sessionStart = ActiveAppsManager.sessionStartTimeMap[packageName] ?: 0L
            val elapsedSession = if (sessionStart > 0L) (now - sessionStart) else 0L

            if (sessionLimit > 0L && sessionStart > 0L) {
                if (elapsedSession >= sessionLimit) {
                    isSessionPromptNeeded = true
                } else {
                    sessionRemainingMs = sessionLimit - elapsedSession
                }
            } else {
                // Agar session mapping blank hai, toh prompt visual block dikhana padega
                isSessionPromptNeeded = true
            }
        }

        // Agar session timeout ho gaya hai, prompt overlay bottom sheet load karenge
        if (isSessionPromptNeeded) {
            NativeOverlayManager.showPromptOverlay(this, packageName, (todayUsage / 60000).toInt(),
                onCloseApp = {
                    openApp = null
                    openAppStart = 0
                    handler.removeCallbacks(blockRunnable)
                    handler.removeCallbacks(promptRunnable)
                    goHome()
                },
                onSelectSession = { minutes ->
                    if (minutes == -1) {
                        ActiveAppsManager.sessionLimitMap[packageName] = Long.MAX_VALUE
                        ActiveAppsManager.sessionStartTimeMap[packageName] = System.currentTimeMillis()
                    } else {
                        val limitMs = minutes.toLong() * 60000L
                        ActiveAppsManager.sessionLimitMap[packageName] = limitMs
                        ActiveAppsManager.sessionStartTimeMap[packageName] = System.currentTimeMillis()
                    }
                    
                    // Dobara checking schedule karenge
                    reloadActiveAppsList()
                    val reTracked = ActiveAppsManager.activeAppsList.find { it.packageName == packageName }
                    if (reTracked != null) {
                        checkLimitsAndSchedule(packageName, reTracked)
                    }
                }
            )
            return
        }

        // C. Handlers ke dynamic single-shot scheduling set karenge
        handler.removeCallbacks(blockRunnable)
        handler.removeCallbacks(promptRunnable)

        // 1. Daily limit timer schedule karenge
        val dailyRemainingMs = allowedLimit - todayUsage
        if (dailyRemainingMs > 0) {
            handler.postDelayed(blockRunnable, dailyRemainingMs)
        }

        // 2. Session limit timer schedule karenge
        if (sessionRemainingMs > 0 && sessionRemainingMs != Long.MAX_VALUE) {
            handler.postDelayed(promptRunnable, sessionRemainingMs)
        }
    }

    /**
     * checkAndTriggerOverlay:
     * Timer fire hone par running usage save karke overlay draw karta hai.
     */
    private fun checkAndTriggerOverlay(isBlockMode: Boolean) {
        val currentApp = openApp ?: return
        val app = ActiveAppsManager.activeAppsList.find { it.packageName == currentApp } ?: return
        val now = System.currentTimeMillis()

        // Usage update karenge
        val duration = now - openAppStart
        if (duration > 0) {
            app.todayUsage += duration
            dbHelper.updateAppUsage(currentApp, app.todayUsage)
            openAppStart = now
        }

        val spentMinutes = (app.todayUsage / 60000).toInt()

        if (isBlockMode) {
            NativeOverlayManager.showBlockOverlay(this, currentApp, spentMinutes) {
                openApp = null
                openAppStart = 0
                handler.removeCallbacks(blockRunnable)
                handler.removeCallbacks(promptRunnable)
                goHome()
            }
        } else {
            // Session limit finish: remove details
            ActiveAppsManager.sessionLimitMap.remove(currentApp)
            ActiveAppsManager.sessionStartTimeMap.remove(currentApp)

            NativeOverlayManager.showPromptOverlay(this, currentApp, spentMinutes,
                onCloseApp = {
                    openApp = null
                    openAppStart = 0
                    handler.removeCallbacks(blockRunnable)
                    handler.removeCallbacks(promptRunnable)
                    goHome()
                },
                onSelectSession = { minutes ->
                    if (minutes == -1) {
                        ActiveAppsManager.sessionLimitMap[currentApp] = Long.MAX_VALUE
                        ActiveAppsManager.sessionStartTimeMap[currentApp] = System.currentTimeMillis()
                    } else {
                        val limitMs = minutes.toLong() * 60000L
                        ActiveAppsManager.sessionLimitMap[currentApp] = limitMs
                        ActiveAppsManager.sessionStartTimeMap[currentApp] = System.currentTimeMillis()
                    }
                    
                    reloadActiveAppsList()
                    val reTracked = ActiveAppsManager.activeAppsList.find { it.packageName == currentApp }
                    if (reTracked != null) {
                        checkLimitsAndSchedule(currentApp, reTracked)
                    }
                }
            )
        }
    }

    private fun reloadActiveAppsList() {
        val list = dbHelper.getActiveAppsFromDb()
        ActiveAppsManager.activeAppsList.clear()
        ActiveAppsManager.activeAppsList.addAll(list)

        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val reminderVal = prefs.all["flutter.reminder_option"]
            val reminderOpt = when (reminderVal) {
                is Int -> reminderVal
                is Long -> reminderVal.toInt()
                is Float -> reminderVal.toInt()
                is Double -> reminderVal.toInt()
                is String -> reminderVal.toIntOrNull() ?: 0
                else -> 0 // Default to 0 (Always Ask)
            }
            val oldOption = ActiveAppsManager.reminderOptionSetting
            ActiveAppsManager.reminderOptionSetting = reminderOpt
            if (oldOption != reminderOpt) {
                ActiveAppsManager.sessionStartTimeMap.clear()
                ActiveAppsManager.sessionLimitMap.clear()
            }
        } catch (e: Exception) {
        }
    }

    private fun goHome() {
        try {
            val success = performGlobalAction(GLOBAL_ACTION_HOME)
            if (!success) {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
            }
        } catch (e: Exception) {
            try {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
            } catch (_: Exception) {}
        }
    }

    // System utility tools (system package checking filters)
    private fun isIgnoredPackage(pkg: String): Boolean {
        if (pkg.isEmpty()) return true
        val lowerPkg = pkg.lowercase()
        if (lowerPkg == "android") return true
        if (lowerPkg == "com.example.testproject") return true
        if (lowerPkg.contains("launcher") ||
            lowerPkg.contains("home") ||
            lowerPkg.contains("systemui") ||
            lowerPkg.contains("settings") ||
            lowerPkg.contains("packageinstaller") ||
            lowerPkg.contains("permissioncontroller") ||
            lowerPkg.contains("inputmethod") ||
            lowerPkg.contains("keyboard") ||
            lowerPkg.contains("ime")
        ) {
            return true
        }
        return false
    }

    companion object {
        var lastDismissedPackage: String? = null
        var lastDismissedTimeMs: Long = 0L
    }

    private fun checkFocusModeAndShowOverlay(packageName: String): Boolean {
        try {
            Log.d("FocusDebug", "===============================================")
            Log.d("FocusDebug", "[1] Event Received for package: '$packageName'")

            // 0. Cooldown check: If user JUST tapped "Close app" for this exact app within the last 3 seconds, suppress re-triggering overlay during background transition
            if (packageName == lastDismissedPackage && (System.currentTimeMillis() - lastDismissedTimeMs) < 3000L) {
                Log.d("FocusDebug", "Suppressing duplicate overlay trigger for closing package '$packageName'")
                return false
            }

            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val allPrefs = prefs.all

            // 1. Read session start time
            val startVal = allPrefs["flutter.focus_session_start_time"]
            val startTimeMs = when (startVal) {
                is Long -> startVal
                is Int -> startVal.toLong()
                is String -> startVal.toLongOrNull() ?: 0L
                else -> 0L
            }

            // 2. Read duration minutes
            val durationVal = allPrefs["flutter.focus_duration_minutes"]
            val durationMinutes = when (durationVal) {
                is Int -> durationVal
                is Long -> durationVal.toInt()
                is String -> durationVal.toIntOrNull() ?: 30
                else -> 30
            }

            val totalMs = durationMinutes * 60 * 1000L
            val elapsedMs = if (startTimeMs > 0L) (System.currentTimeMillis() - startTimeMs) else 0L
            val isSessionActive = startTimeMs > 0L && elapsedMs < totalMs

            Log.d("FocusDebug", "[2] Local Prefs Fetched -> StartTime: $startTimeMs, Duration: $durationMinutes min, Elapsed: ${elapsedMs / 1000}s, IsActive: $isSessionActive")

            if (!isSessionActive) {
                Log.d("FocusDebug", "[3] Result: Focus Session is NOT active (or expired). Overlay will NOT trigger.")
                return false
            }

            // 3. Read blocked packages list
            val rawBlockedList = mutableSetOf<String>()
            val rawAppsObj = allPrefs["flutter.focus_blocked_apps"]

            if (rawAppsObj is String) {
                var jsonStr = rawAppsObj.trim()
                val bracketPos = jsonStr.indexOf('[')
                val endBracketPos = jsonStr.lastIndexOf(']')
                if (bracketPos != -1 && endBracketPos != -1 && endBracketPos > bracketPos) {
                    jsonStr = jsonStr.substring(bracketPos, endBracketPos + 1)
                }
                try {
                    val array = org.json.JSONArray(jsonStr)
                    for (i in 0 until array.length()) {
                        rawBlockedList.add(array.getString(i))
                    }
                } catch (e: Exception) {
                    Log.e("FocusDebug", "Error parsing json array: ${e.message} for raw: $rawAppsObj")
                }
            } else if (rawAppsObj is Set<*>) {
                rawAppsObj.filterIsInstance<String>().forEach { rawBlockedList.add(it) }
            } else if (rawAppsObj is List<*>) {
                rawAppsObj.filterIsInstance<String>().forEach { rawBlockedList.add(it) }
            }

            val isMatched = rawBlockedList.contains(packageName)
            Log.d("FocusDebug", "[3] Blocked Apps List in Local: $rawBlockedList")
            Log.d("FocusDebug", "[4] App Match Check -> Package '$packageName' in Blocked List? => $isMatched")

            if (isMatched) {
                Log.d("FocusDebug", "[5] SUCCESS: Triggering Native Focus Overlay Pop-up NOW for '$packageName'!")
                NativeOverlayManager.showFocusOverlay(
                    this,
                    packageName,
                    onCloseApp = {
                        Log.d("FocusDebug", "User clicked Close App on Focus Overlay for package '$packageName'")
                        lastDismissedPackage = packageName
                        lastDismissedTimeMs = System.currentTimeMillis()
                        openApp = null
                        openAppStart = 0
                        goHome()
                    }
                )
                return true
            } else {
                Log.d("FocusDebug", "[5] App '$packageName' is not in blocked list. Overlay will NOT trigger.")
            }
        } catch (e: Exception) {
            Log.e("FocusDebug", "Exception in checkFocusModeAndShowOverlay", e)
        }
        return false
    }

    private fun notifyAccessibilityStatusChanged(enabled: Boolean) {
        try {
            val json = JSONObject()
            json.put("method", "accessibilityStatusChanged")
            val args = JSONObject()
            args.put("enabled", enabled)
            json.put("args", args)
            FlutterBackgroundServicePlugin.servicePipe.invoke(json)
        } catch (e: Exception) {
        }
    }

    override fun onInterrupt() {
    }

    override fun onUnbind(intent: Intent?): Boolean {
        handler.removeCallbacksAndMessages(null)
        NativeOverlayManager.removeOverlay()
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_accessibility_enabled", false).apply()
            notifyAccessibilityStatusChanged(false)
        } catch (e: Exception) {
        }
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        NativeOverlayManager.removeOverlay()
        try {
            if (screenReceiver != null) {
                unregisterReceiver(screenReceiver)
            }
        } catch (e: Exception) {
        }
        super.onDestroy()
    }
}