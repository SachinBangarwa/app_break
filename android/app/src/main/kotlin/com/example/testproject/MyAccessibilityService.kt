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

/**
 * Android Accessibility Service:
 * Jab user Accessibility permission enable karta hai, tab ye service active ho jati hai.
 * Ye service real-time me window state changes (app opening/closing) ko observe karti hai.
 */
class MyAccessibilityService : AccessibilityService() {

    private var screenReceiver: BroadcastReceiver? = null

    // Service initialize hone par Screen Off event listener set karta hai
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

    // Service connect hone par SharedPreferences me accessibility status true save karta hai
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

    // Dart Background Service ko Accessibility status (ON/OFF) change hone ka notify karta hai
    private fun notifyAccessibilityStatusChanged(enabled: Boolean = true) {
        try {
            val json = JSONObject()
            json.put("method", "accessibilityStatusChanged")
            val args = JSONObject()
            args.put("enabled", enabled)
            json.put("args", args)
            FlutterBackgroundServicePlugin.servicePipe.invoke(json)
            Log.d("MyAccessibilityService", "Invoked accessibilityStatusChanged event with enabled=$enabled")
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error invoking accessibilityStatusChanged: ${e.message}")
        }
    }

    // Jab bhi screen par naya app ya window open hoti hai, ye event trigger hota hai
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: ""
            Log.d("MyAccessibilityService", "Window State Changed: $packageName")
            println("--- [Accessibility Service] Active Package: $packageName ---")

            handlePackageChanged(packageName)
        }
    }

    // Active foreground app change hone par Dart Isolate ko IPC method call (packageNameChanged) dwara notify karta hai
    private fun handlePackageChanged(packageName: String) {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.active_foreground_package", packageName).apply()

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

    // Service disconnect hone par accessibility status false karta hai aur Dart side ko notify karta hai
    override fun onUnbind(intent: Intent?): Boolean {
        Log.d("MyAccessibilityService", "Service Unbound")
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("flutter.is_accessibility_enabled", false).apply()

            val json = JSONObject()
            json.put("method", "packageNameChanged")
            val args = JSONObject()
            args.put("packageName", "")
            json.put("args", args)
            FlutterBackgroundServicePlugin.servicePipe.invoke(json)

            notifyAccessibilityStatusChanged(false)
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error setting inactive status: ${e.message}")
        }
        return super.onUnbind(intent)
    }

    // Service destroy hone par screen receiver unregister karta hai
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

            val json = JSONObject()
            json.put("method", "packageNameChanged")
            val args = JSONObject()
            args.put("packageName", "")
            json.put("args", args)
            FlutterBackgroundServicePlugin.servicePipe.invoke(json)

            notifyAccessibilityStatusChanged()
        } catch (e: Exception) {
            Log.e("MyAccessibilityService", "Error setting inactive status: ${e.message}")
        }

        super.onDestroy()
    }
}