//package com.example.testproject
//
//import android.accessibilityservice.AccessibilityService
//import android.view.accessibility.AccessibilityEvent
//import android.util.Log
//import android.content.Context
//import android.content.Intent
//import android.content.BroadcastReceiver
//import android.content.IntentFilter
//import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin
//import org.json.JSONObject
//
//class MyAccessibilityService : AccessibilityService() {
//
//    private var screenReceiver: BroadcastReceiver? = null
//
//    override fun onCreate() {
//        super.onCreate()
//        Log.d("MyAccessibilityService", "Service Created")
//        try {
//            screenReceiver = object : BroadcastReceiver() {
//                override fun onReceive(context: Context?, intent: Intent?) {
//                    if (intent?.action == Intent.ACTION_SCREEN_OFF) {
//                        Log.d("MyAccessibilityService", "Screen Off Detected")
//                        handlePackageChanged("")
//                    }
//                }
//            }
//            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
//            registerReceiver(screenReceiver, filter)
//        } catch (e: Exception) {
//            Log.e("MyAccessibilityService", "Error registering screenReceiver: ${e.message}")
//        }
//    }
//
//    override fun onServiceConnected() {
//        super.onServiceConnected()
//        Log.d("MyAccessibilityService", "Service Connected")
//        try {
//            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
//            prefs.edit().putBoolean("flutter.is_accessibility_enabled", true).apply()
//        } catch (e: Exception) {
//            Log.e("MyAccessibilityService", "Error setting active status: ${e.message}")
//        }
//    }
//
//    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
//        if (event == null) return
//
//        // Listen to window state changes (i.e. app opens, screen changes)
//        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
//            val packageName = event.packageName?.toString() ?: ""
//            Log.d("MyAccessibilityService", "Window State Changed: $packageName")
//            println("--- [Accessibility Service] Active Package: $packageName ---")
//
//            handlePackageChanged(packageName)
//        }
//    }
//
//    private fun handlePackageChanged(packageName: String) {
//        try {
//            // 1. Update SharedPreferences
//            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
//            prefs.edit().putString("flutter.active_foreground_package", packageName).apply()
//
//            // 2. Invoke packageNameChanged event in FlutterBackgroundService via servicePipe
//            val json = JSONObject()
//            json.put("method", "packageNameChanged")
//
//            val args = JSONObject()
//            args.put("packageName", packageName)
//            json.put("args", args)
//
//            FlutterBackgroundServicePlugin.servicePipe.invoke(json)
//            Log.d("MyAccessibilityService", "Invoked packageNameChanged event with: $packageName")
//        } catch (e: Exception) {
//            Log.e("MyAccessibilityService", "Error handling package change: ${e.message}")
//        }
//    }
//
//    override fun onInterrupt() {
//        Log.d("MyAccessibilityService", "Service Interrupted")
//    }
//
//    override fun onUnbind(intent: Intent?): Boolean {
//        Log.d("MyAccessibilityService", "Service Unbound")
//        try {
//            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
//            prefs.edit().putBoolean("flutter.is_accessibility_enabled", false).apply()
//
//            // Notify Dart background service that accessibility is disabled
//            val json = JSONObject()
//            json.put("method", "packageNameChanged")
//            val args = JSONObject()
//            args.put("packageName", "")
//            json.put("args", args)
//            FlutterBackgroundServicePlugin.servicePipe.invoke(json)
//        } catch (e: Exception) {
//            Log.e("MyAccessibilityService", "Error setting inactive status: ${e.message}")
//        }
//        return super.onUnbind(intent)
//    }
//
//    override fun onDestroy() {
//        Log.d("MyAccessibilityService", "Service Destroyed")
//        try {
//            if (screenReceiver != null) {
//                unregisterReceiver(screenReceiver)
//            }
//        } catch (e: Exception) {
//            Log.e("MyAccessibilityService", "Error unregistering receiver: ${e.message}")
//        }
//        try {
//            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
//            prefs.edit().putBoolean("flutter.is_accessibility_enabled", false).apply()
//
//            // Notify Dart background service that accessibility is disabled
//            val json = JSONObject()
//            json.put("method", "packageNameChanged")
//            val args = JSONObject()
//            args.put("packageName", "")
//            json.put("args", args)
//            FlutterBackgroundServicePlugin.servicePipe.invoke(json)
//        } catch (e: Exception) {
//            Log.e("MyAccessibilityService", "Error setting inactive status: ${e.message}")
//        }
//
//        super.onDestroy()
//    }
//}
//
package com.example.testproject

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.util.Log
import android.content.Context
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin
import org.json.JSONObject

class MyAccessibilityService : AccessibilityService() {

    private var screenReceiver: BroadcastReceiver? = null

    override fun onCreate() {
        super.onCreate()
        Log.d("MyAccessibilityService", "Service Created")
        try {
            screenReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                        Log.d("MyAccessibilityService", "Screen Off Detected")
                        handlePackageChanged("")
                    }
                }
            }
            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
            registerReceiver(screenReceiver, filter)
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error registering screenReceiver: ${e.message}")
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("MyAccessibilityService", "Service Connected")
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_accessibility_enabled", true).apply()

            notifyAccessibilityStatusChanged()
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error setting active status: ${e.message}")
        }
    }

    // Tells the Dart background service that the accessibility ON/OFF status
    // has changed, so it can immediately re-configure (stop/start polling)
    // instead of waiting for the next 4-sec poll tick.
    private fun notifyAccessibilityStatusChanged() {
        try {
            val json = JSONObject()
            json.put("method", "accessibilityStatusChanged")
            json.put("args", JSONObject())
            FlutterBackgroundServicePlugin.servicePipe.invoke(json)
            Log.d("MyAccessibilityService", "Invoked accessibilityStatusChanged event")
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error invoking accessibilityStatusChanged: ${e.message}")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Listen to window state changes (i.e. app opens, screen changes)
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: ""
            Log.d("MyAccessibilityService", "Window State Changed: $packageName")
            println("--- [Accessibility Service] Active Package: $packageName ---")

            handlePackageChanged(packageName)
        }
    }

    private fun handlePackageChanged(packageName: String) {
        try {
            // 1. Update SharedPreferences
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.active_foreground_package", packageName).apply()

            // 2. Invoke packageNameChanged event in FlutterBackgroundService via servicePipe
            val json = JSONObject()
            json.put("method", "packageNameChanged")

            val args = JSONObject()
            args.put("packageName", packageName)
            json.put("args", args)

            FlutterBackgroundServicePlugin.servicePipe.invoke(json)
            Log.d("MyAccessibilityService", "Invoked packageNameChanged event with: $packageName")
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error handling package change: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.d("MyAccessibilityService", "Service Interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.d("MyAccessibilityService", "Service Unbound")
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_accessibility_enabled", false).apply()

            // Notify Dart background service that accessibility is disabled
            val json = JSONObject()
            json.put("method", "packageNameChanged")
            val args = JSONObject()
            args.put("packageName", "")
            json.put("args", args)
            FlutterBackgroundServicePlugin.servicePipe.invoke(json)

            // Tell Dart side to re-configure immediately (restart polling if needed)
            notifyAccessibilityStatusChanged()
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error setting inactive status: ${e.message}")
        }
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        Log.d("MyAccessibilityService", "Service Destroyed")
        try {
            if (screenReceiver != null) {
                unregisterReceiver(screenReceiver)
            }
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error unregistering receiver: ${e.message}")
        }
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_accessibility_enabled", false).apply()

            // Notify Dart background service that accessibility is disabled
            val json = JSONObject()
            json.put("method", "packageNameChanged")
            val args = JSONObject()
            args.put("packageName", "")
            json.put("args", args)
            FlutterBackgroundServicePlugin.servicePipe.invoke(json)

            // Tell Dart side to re-configure immediately (restart polling if needed)
            notifyAccessibilityStatusChanged()
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error setting inactive status: ${e.message}")
        }

        super.onDestroy()
    }
}