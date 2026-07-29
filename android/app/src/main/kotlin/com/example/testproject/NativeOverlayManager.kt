package com.example.testproject

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.LinearLayout

/**
 * NativeOverlayManager:
 * Yeh manager class system WindowManager ke zariye native layouts (Block aur Prompt) ko screen par draw karti hai.
 * Isme zero Flutter/Dart dependency hai aur ye 100% Android UI systems ka use karti hai.
 */
object NativeOverlayManager {
    private var windowManager: WindowManager? = null
    private var currentOverlayView: View? = null
    var activeOverlayPackage: String? = null // Tracks currently active overlay app

    private val focusHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var focusRunnable: Runnable? = null

    /**
     * Kisi bhi chalu overlay view ko screen se safai se remove (delete) karta hai.
     */
    fun removeOverlay() {
        try {
            focusRunnable?.let { focusHandler.removeCallbacks(it) }
            if (windowManager != null && currentOverlayView != null) {
                // WindowManager se view delete karenge
                windowManager?.removeView(currentOverlayView)
                currentOverlayView = null
                activeOverlayPackage = null // Clear tracker
            }
        } catch (e: Exception) {
        }
    }

    /**
     * showBlockOverlay:
     * Daily Limit exhaust hone par red icon ke sath screen blocker display karta hai.
     */
    fun showBlockOverlay(
        context: Context,
        packageName: String,
        spentMinutes: Int,
        onCloseApp: () -> Unit
    ) {
        // Pehle se chal rahe overlay ko remove karenge
        removeOverlay()
        activeOverlayPackage = packageName

        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // Layout inflate (load) karenge
        val inflater = context.getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val view = inflater.inflate(R.layout.native_block_overlay, null)
        currentOverlayView = view

        // Subtext TextView update karenge taaki user ko spent time aur warning dikhe
        val subtext = view.findViewById<TextView>(R.id.block_subtext)
        subtext.text = "You have used this app for $spentMinutes m today.\nPlease take a break!"

        // Close App Button setup
        val btnClose = view.findViewById<Button>(R.id.btn_close_app)
        
        // Sleek black rounded button background draw karenge programmatically
        val buttonBackground = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 16f * context.resources.displayMetrics.density // 16dp rounded corners
            setColor(Color.parseColor("#111111")) // Solid black color
        }
        btnClose.background = buttonBackground

        // Close button click listener
        btnClose.setOnClickListener {
            removeOverlay()
            onCloseApp()
        }

        // Window Layout Parameters set karenge
        val params = getOverlayLayoutParams()
        
        // View ko window manager me add kar denge taaki wo screen par sabse upar dikhe
        windowManager?.addView(view, params)
    }

    /**
     * showPromptOverlay:
     * Session limit prompt select karne ke liye mindful intent window show karta hai (Bottom sheet features ke sath).
     */
    fun showPromptOverlay(
        context: Context,
        packageName: String,
        spentMinutes: Int,
        onCloseApp: () -> Unit,
        onSelectSession: (minutes: Int) -> Unit
    ) {
        removeOverlay()
        activeOverlayPackage = packageName

        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val inflater = context.getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val view = inflater.inflate(R.layout.native_prompt_overlay, null)
        currentOverlayView = view

        // Subtext update karenge
        val subtext = view.findViewById<TextView>(R.id.prompt_subtext)
        subtext.text = "Time spent: $spentMinutes m"

        val btnClose = view.findViewById<Button>(R.id.btn_prompt_close)
        val btnContinue = view.findViewById<Button>(R.id.btn_prompt_continue)
        val bottomSheet = view.findViewById<LinearLayout>(R.id.bottom_sheet_container)

        // Close App Button shape styling
        val closeBtnBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 16f * context.resources.displayMetrics.density
            setColor(Color.parseColor("#111111"))
        }
        btnClose.background = closeBtnBg

        // Buttons listeners
        btnClose.setOnClickListener {
            removeOverlay()
            onCloseApp()
        }

        // Continue button click logic:
        // If a preset reminder is set, apply it immediately and close overlay. Otherwise, show selector list.
        btnContinue.setOnClickListener {
            val reminderOpt = ActiveAppsManager.reminderOptionSetting
            if (reminderOpt == -1) {
                removeOverlay()
                onSelectSession(-1)
            } else if (reminderOpt > 0) {
                removeOverlay()
                onSelectSession(reminderOpt)
            } else {
                bottomSheet.visibility = View.VISIBLE
            }
        }

        // Bottom Sheet option buttons key assignments
        setupOptionButton(context, view.findViewById(R.id.btn_opt_1min), 1, onSelectSession)
        setupOptionButton(context, view.findViewById(R.id.btn_opt_5min), 5, onSelectSession)
        setupOptionButton(context, view.findViewById(R.id.btn_opt_10min), 10, onSelectSession)
        setupOptionButton(context, view.findViewById(R.id.btn_opt_15min), 15, onSelectSession)
        setupOptionButton(context, view.findViewById(R.id.btn_opt_30min), 30, onSelectSession)

        // Cancel button sheet close karne ke liye
        val btnCancel = view.findViewById<Button>(R.id.btn_opt_cancel)
        
        val cancelBtnBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 12f * context.resources.displayMetrics.density
            setColor(Color.parseColor("#E0E0E0"))
        }
        btnCancel.background = cancelBtnBg
        btnCancel.setOnClickListener {
            bottomSheet.visibility = View.GONE
        }

        val params = getOverlayLayoutParams()
        windowManager?.addView(view, params)
    }

    /**
     * Session option buttons ko design aur functionality assign karne ka common helper.
     */
    private fun setupOptionButton(
        context: Context,
        btn: Button,
        minutes: Int,
        onSelect: (minutes: Int) -> Unit
    ) {
        val btnBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 12f * context.resources.displayMetrics.density // 12dp rounded corners
            setColor(Color.parseColor("#FFFFFF")) // White button
            setStroke(2, Color.parseColor("#DDDDDD")) // Border
        }
        btn.background = btnBg

        btn.setOnClickListener {
            removeOverlay() // Select hote hi overlay remove hoga
            onSelect(minutes) // Selected time session start ho jayega
        }
    }

    /**
     * showFocusOverlay:
     * Focus Session active hone par full-screen Focus overlay pop-up show karta hai.
     */
    fun showFocusOverlay(
        context: Context,
        packageName: String,
        onCloseApp: () -> Unit,
        onStopFocusSession: () -> Unit
    ) {
        removeOverlay()
        activeOverlayPackage = packageName

        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val inflater = context.getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val view = inflater.inflate(R.layout.native_focus_overlay, null)
        currentOverlayView = view

        val txtTimer = view.findViewById<TextView>(R.id.focus_timer_text)
        val btnClose = view.findViewById<Button>(R.id.btn_focus_close_app)
        val btnStop = view.findViewById<TextView>(R.id.btn_stop_focus)

        // Outlined button background design
        val closeBtnBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 16f * context.resources.displayMetrics.density
            setColor(Color.parseColor("#F7F8FA"))
            setStroke((1.2f * context.resources.displayMetrics.density).toInt(), Color.parseColor("#000000"))
        }
        btnClose.background = closeBtnBg

        // Close app action
        btnClose.setOnClickListener {
            removeOverlay()
            onCloseApp()
        }

        // Stop Focus Session action
        btnStop.setOnClickListener {
            removeOverlay()
            onStopFocusSession()
        }

        // Live timer update every 1 second
        focusRunnable?.let { focusHandler.removeCallbacks(it) }
        focusRunnable = object : Runnable {
            override fun run() {
                val remainingSecs = getFocusRemainingSeconds(context)
                if (remainingSecs <= 0) {
                    removeOverlay()
                    onCloseApp()
                } else {
                    val hours = remainingSecs / 3600
                    val minutes = (remainingSecs % 3600) / 60
                    val secs = remainingSecs % 60
                    val timerStr = if (hours > 0) {
                        String.format("%02d:%02d:%02d", hours, minutes, secs)
                    } else {
                        String.format("%02d:%02d", minutes, secs)
                    }
                    txtTimer.text = timerStr
                    focusHandler.postDelayed(this, 1000L)
                }
            }
        }
        focusRunnable?.let { focusHandler.post(it) }

        val params = getOverlayLayoutParams()
        try {
            windowManager?.addView(view, params)
        } catch (e: Exception) {
        }
    }

    private fun getFocusRemainingSeconds(context: Context): Long {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val allPrefs = prefs.all

            val startVal = allPrefs["flutter.focus_session_start_time"]
            val startTimeMs = when (startVal) {
                is Long -> startVal
                is Int -> startVal.toLong()
                is String -> startVal.toLongOrNull() ?: 0L
                else -> 0L
            }
            if (startTimeMs <= 0L) return 0L

            val durationVal = allPrefs["flutter.focus_duration_minutes"]
            val durationMinutes = when (durationVal) {
                is Int -> durationVal
                is Long -> durationVal.toInt()
                is String -> durationVal.toIntOrNull() ?: 30
                else -> 30
            }

            val totalMs = durationMinutes * 60 * 1000L
            val elapsedMs = System.currentTimeMillis() - startTimeMs
            val remainingMs = totalMs - elapsedMs
            return if (remainingMs > 0) remainingMs / 1000L else 0L
        } catch (e: Exception) {
            return 0L
        }
    }

    /**
     * Full screen application overlay layout parameters return karta hai.
     */
    private fun getOverlayLayoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or 
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        )
    }
}
