package com.example.testproject

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings
import android.text.TextUtils
import android.content.ComponentName
import android.accessibilityservice.AccessibilityService

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.testproject/package_change"
    private var methodChannel: MethodChannel? = null
    private var packageReceiver: BroadcastReceiver? = null
    private var notificationReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkNotificationListenerPermission" -> {
                    result.success(isNotificationServiceEnabled(this))
                }

                "openNotificationListenerSettings" -> {
                    try {
                        val intent =
                            Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Could not open settings: ${e.message}", null)
                    }
                }

                "checkAccessibilityPermission" -> {
                    result.success(isAccessibilityServiceEnabled(this, MyAccessibilityService::class.java))
                }

                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Could not open settings: ${e.message}", null)
                    }
                }

                "launchNotificationIntent" -> {
                    val idRaw = call.argument<Any>("id")
                    // Handle Long representation which can sometimes come as Integer or Long from Dart
                    val id = when (idRaw) {
                        is Int -> idRaw.toLong()
                        is Long -> idRaw
                        else -> null
                    }
                    val packageName = call.argument<String>("packageName") ?: ""
                    var launched = false

                    if (id != null) {
                        val pendingIntent = MyNotificationListenerService.pendingIntentsMap[id]
                        if (pendingIntent != null) {
                            try {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                    val options = android.app.ActivityOptions.makeBasic()
                                        .setPendingIntentBackgroundActivityStartMode(android.app.ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                                        .toBundle()
                                    pendingIntent.send(this, 0, null, null, null, null, options)
                                } else {
                                    pendingIntent.send(this, 0, null)
                                }
                                launched = true
                                android.util.Log.d("MainActivity", "Successfully launched PendingIntent for ID: $id")
                            } catch (e: Exception) {
                                android.util.Log.e("MainActivity", "Error sending PendingIntent: ${e.message}")
                            }
                        } else {
                            android.util.Log.w("MainActivity", "PendingIntent was null in map for ID: $id (maybe the app was restarted or recompiled?)")
                        }
                    }

                    // Fallback: Launch app normally by package name
                    if (!launched && packageName.isNotEmpty()) {
                        try {
                            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                            if (launchIntent != null) {
                                startActivity(launchIntent)
                                launched = true
                                android.util.Log.d("MainActivity", "Fallback: Launched app package: $packageName")
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error launching app fallback: ${e.message}")
                        }
                    }

                    result.success(launched)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isAccessibilityServiceEnabled(context: Context, serviceClass: Class<out AccessibilityService>): Boolean {
        val expectedComponentName = ComponentName(context, serviceClass)
        val enabledServicesSetting = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServicesSetting)

        while (colonSplitter.hasNext()) {
            val componentNameString = colonSplitter.next()
            val enabledService = ComponentName.unflattenFromString(componentNameString)
            if (enabledService != null && enabledService == expectedComponentName) {
                return true
            }
        }
        return false
    }

    private fun isNotificationServiceEnabled(context: Context): Boolean {
        val pkgName = context.packageName
        val flat = android.provider.Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        )
        if (flat != null && flat.isNotEmpty()) {
            val names = flat.split(":")
            for (name in names) {
                val cn = android.content.ComponentName.unflattenFromString(name)
                if (cn != null && cn.packageName == pkgName) {
                    return true
                }
            }
        }
        return false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        packageReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val action = intent.action
                val packageName = intent.data?.schemeSpecificPart ?: return

                when (action) {
                    Intent.ACTION_PACKAGE_ADDED -> {
                        val isReplacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                        if (!isReplacing) {
                            println("--- [MainActivity Kotlin] Installed Package: $packageName ---")
                            methodChannel?.invokeMethod("packageAdded", packageName)
                        }
                    }

                    Intent.ACTION_PACKAGE_REMOVED -> {
                        val isReplacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                        if (!isReplacing) {
                            println("--- [MainActivity Kotlin] Uninstalled Package: $packageName ---")
                            methodChannel?.invokeMethod("packageRemoved", packageName)
                        }
                    }
                }
            }
        }

        notificationReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                methodChannel?.invokeMethod("notificationSaved", null)
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addDataScheme("package")
        }

        val notifFilter = IntentFilter("com.example.testproject.NOTIFICATION_SAVED")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(packageReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(notificationReceiver, notifFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(packageReceiver, filter)
            registerReceiver(notificationReceiver, notifFilter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        packageReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // already unregistered, safe to ignore
            }
        }
        packageReceiver = null

        notificationReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // already unregistered, safe to ignore
            }
        }
        notificationReceiver = null
    }
}