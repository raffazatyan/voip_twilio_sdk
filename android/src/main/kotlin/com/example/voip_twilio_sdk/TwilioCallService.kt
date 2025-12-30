package com.example.voip_twilio_sdk

import android.app.*
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.graphics.drawable.IconCompat

class TwilioCallService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private val CHANNEL_ID = "PhoneCallChannel"
    private val NOTIFICATION_ID = 12345 // Same as TwilioVoiceChannelHandler
    private var callContactPhone: String? = null
    private var isMuted: Boolean = false
    private var isSpeakerOn: Boolean = false
    private var callStartTime: Long = 0

    companion object {
        private const val TAG = "TwilioCallService"
        private var instance: TwilioCallService? = null

        fun getInstance(): TwilioCallService? = instance
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "Twilio call service created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Twilio call service starting")
        
        callContactPhone = intent?.getStringExtra("call_contact_phone") ?: "Unknown"
        isMuted = intent?.getBooleanExtra("is_muted", false) ?: false
        isSpeakerOn = intent?.getBooleanExtra("is_speaker_on", false) ?: false
        
        Log.d(TAG, "Service configured: contact=$callContactPhone, muted=$isMuted, speaker=$isSpeakerOn")
        val notification = createCallStyleNotification(showTimer = false)

        // Start foreground service with retry logic
        startForegroundServiceWithRetry(notification, maxRetries = 3)

        acquireWakeLock()

        return START_STICKY // Restart if killed
    }

    private fun startForegroundServiceWithRetry(notification: Notification, maxRetries: Int = 3) {
        var retryCount = 0
        val handler = Handler(Looper.getMainLooper())
        
        fun attemptStart() {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // Android 14+ requires FOREGROUND_SERVICE_MICROPHONE permission
                    // and app must be in foreground when starting
                    if (isAppInForeground()) {
                        try {
                            startForeground(
                                NOTIFICATION_ID,
                                notification,
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                            )
                            Log.d(TAG, "Foreground service started with microphone type")
                            return
                        } catch (e: SecurityException) {
                            Log.w(TAG, "SecurityException starting foreground service with microphone type: ${e.message}")
                            // Fall through to try without type
                        }
                    } else {
                        Log.w(TAG, "App not in foreground, will try without microphone type")
                    }
                    
                    // Try without type as fallback
                    try {
                        startForeground(NOTIFICATION_ID, notification)
                        Log.d(TAG, "Foreground service started without type (fallback)")
                        return
                    } catch (fallbackException: SecurityException) {
                        Log.w(TAG, "SecurityException starting foreground service without type: ${fallbackException.message}")
                        if (retryCount < maxRetries) {
                            retryCount++
                            val delayMs = (100 * retryCount).toLong() // Exponential backoff: 100ms, 200ms, 300ms
                            Log.d(TAG, "Retrying foreground service start in ${delayMs}ms (attempt $retryCount/$maxRetries)")
                            handler.postDelayed({ attemptStart() }, delayMs)
                            return
                        }
                    } catch (fallbackException: Exception) {
                        Log.w(TAG, "Failed to start foreground service even without type: ${fallbackException.message}")
                        // Don't throw - call will continue without foreground service notification
                        return
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    // Android 10-13: Try with type, fallback without type
                    try {
                        startForeground(
                            NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                        )
                        Log.d(TAG, "Foreground service started with microphone type")
                        return
                    } catch (e: SecurityException) {
                        Log.w(TAG, "SecurityException starting foreground service with microphone type: ${e.message}")
                        try {
                            startForeground(NOTIFICATION_ID, notification)
                            Log.d(TAG, "Foreground service started without type (fallback)")
                            return
                        } catch (fallbackException: Exception) {
                            Log.w(TAG, "Failed to start foreground service without type: ${fallbackException.message}")
                            return
                        }
                    }
                } else {
                    // Android 9 and below: No type needed
                    startForeground(NOTIFICATION_ID, notification)
                    Log.d(TAG, "Foreground service started")
                    return
                }
            } catch (e: Exception) {
                Log.w(TAG, "Unexpected error starting foreground service: ${e.message}")
                if (retryCount < maxRetries) {
                    retryCount++
                    val delayMs = (100 * retryCount).toLong()
                    Log.d(TAG, "Retrying foreground service start in ${delayMs}ms (attempt $retryCount/$maxRetries)")
                    handler.postDelayed({ attemptStart() }, delayMs)
                } else {
                    Log.w(TAG, "Max retries reached, giving up on foreground service notification")
                    // Don't throw - call will continue without foreground service notification
                }
            }
        }
        
        attemptStart()
    }
    
    private fun isAppInForeground(): Boolean {
        return try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningTasks = activityManager.getRunningTasks(1)
            if (runningTasks.isNotEmpty()) {
                val topActivity = runningTasks[0].topActivity
                topActivity?.packageName == packageName
            } else {
                false
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error checking if app is in foreground: ${e.message}")
            // Default to true to allow service to start
            true
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Twilio call service destroyed")
        instance = null
        releaseWakeLock()
        
        // Dismiss notification
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping foreground service: ${e.message}", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "VoipTwilioSdk:TwilioCallWakeLock"
            )
            wakeLock?.acquire(10 * 60 * 60 * 1000L) // 10 hours max
            Log.d(TAG, "Twilio call wake lock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.takeIf { it.isHeld }?.apply {
                release()
                Log.d(TAG, "Twilio call wake lock released")
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wake lock", e)
        }
    }

    private fun createCallStyleNotification(showTimer: Boolean = true): Notification {
        val phoneNumber = callContactPhone ?: return createFallbackNotification()
        val packageName = this.packageName

        // Main notification intent (opens app)
        val notificationIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            setPackage(packageName)
        }

        val pendingIntent = try {
            PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error creating PendingIntent: ${e.message}")
            return createFallbackNotification()
        }

        // Hang Up action
        val hangUpActionIntent = Intent("com.example.voip_twilio_sdk.CALL_HANG_UP").apply {
            setPackage(packageName)
        }
        val hangUpPendingIntent = try {
            PendingIntent.getBroadcast(
                this,
                100,
                hangUpActionIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error creating hang up PendingIntent: ${e.message}")
            null
        }

        // Toggle Mute action
        val muteIntent = Intent("com.example.voip_twilio_sdk.CALL_TOGGLE_MUTE").apply {
            setPackage(packageName)
        }
        val mutePendingIntent = try {
            PendingIntent.getBroadcast(
                this,
                101,
                muteIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error creating mute PendingIntent: ${e.message}")
            null
        }

        // Toggle Speaker action
        val speakerIntent = Intent("com.example.voip_twilio_sdk.CALL_TOGGLE_SPEAKER").apply {
            setPackage(packageName)
        }
        val speakerPendingIntent = try {
            PendingIntent.getBroadcast(
                this,
                102,
                speakerIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error creating speaker PendingIntent: ${e.message}")
            null
        }

        // Create Person object for CallStyle
        val person = Person.Builder()
            .setName(phoneNumber)
            .build()
        
        // Hang up intent is required for CallStyle
        val hangUpActionPendingIntent = hangUpPendingIntent ?: run {
            Log.e(TAG, "Hang up PendingIntent is null, cannot create CallStyle")
            return createFallbackNotification()
        }
        
        // Build CallStyle - requires fullScreenIntent for non-foreground service
        val fullScreenIntent = PendingIntent.getActivity(
            this,
            200,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        val callStyle = NotificationCompat.CallStyle.forOngoingCall(
            person,
            hangUpActionPendingIntent
        )
        
        // Small icon for notification (use system icon as default, can be customized)
        val smallIconRes = getDrawableResourceId("ic_call_notification", android.R.drawable.ic_menu_call)
        
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(fullScreenIntent, true) // Required for CallStyle
            .setAutoCancel(false) // Don't auto-cancel during active call
            .setOngoing(true) // Make it ongoing so it can't be swiped away
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setStyle(callStyle)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        
        // Add actions through builder (not through CallStyle)
        if (mutePendingIntent != null) {
            val muteIconRes = if (isMuted) {
                getDrawableResourceId("ic_call_unmute", android.R.drawable.ic_media_play)
            } else {
                getDrawableResourceId("ic_call_mute", android.R.drawable.ic_media_pause)
            }
            val muteIconCompat = IconCompat.createWithResource(this, muteIconRes)
            val muteLabel = if (isMuted) "Unmute" else "Mute"
            val muteActionBuilder = NotificationCompat.Action.Builder(
                muteIconCompat,
                muteLabel,
                mutePendingIntent
            )
            muteActionBuilder.setSemanticAction(
                if (isMuted) NotificationCompat.Action.SEMANTIC_ACTION_MUTE else NotificationCompat.Action.SEMANTIC_ACTION_UNMUTE
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                muteActionBuilder.setContextual(true)
            }
            notificationBuilder.addAction(muteActionBuilder.build())
        }
        
        if (speakerPendingIntent != null) {
            val speakerIconRes = if (isSpeakerOn) {
                getDrawableResourceId("ic_call_receiver", android.R.drawable.ic_menu_revert)
            } else {
                getDrawableResourceId("ic_call_speaker", android.R.drawable.ic_menu_view)
            }
            val speakerIconCompat = IconCompat.createWithResource(this, speakerIconRes)
            val speakerLabel = if (isSpeakerOn) "Receiver" else "Speaker"
            val speakerActionBuilder = NotificationCompat.Action.Builder(
                speakerIconCompat,
                speakerLabel,
                speakerPendingIntent
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                speakerActionBuilder.setContextual(true)
            }
            notificationBuilder.addAction(speakerActionBuilder.build())
        }
        
        // Only enable chronometer when call is connected (showTimer = true)
        if (showTimer && callStartTime > 0) {
            notificationBuilder
                .setUsesChronometer(true)
                .setWhen(callStartTime)
        }

        return notificationBuilder.build()
    }

    private fun createFallbackNotification(): Notification {
        val smallIconRes = getDrawableResourceId("ic_call", android.R.drawable.ic_menu_call)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Call Active")
            .setContentText(callContactPhone ?: "Ongoing call")
            .setSmallIcon(smallIconRes)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setAutoCancel(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Phone Call Status",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Shows when app is on a phone call"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(null, null)
                enableVibration(false)
                enableLights(false)
                setAllowBubbles(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            try {
                manager?.createNotificationChannel(channel)
                Log.d(TAG, " Call notification channel created")
            } catch (e: Exception) {
                Log.e(TAG, " Error creating call notification channel: ${e.message}")
            }
        }
    }

    /**
     * Gets drawable resource ID by name, with fallback to default
     * 
     * First tries to find the icon in the plugin package, then in the app package
     * (allowing app to override plugin icons), then falls back to system icon.
     * 
     * @param resourceName Name of the drawable resource (without extension)
     * @param fallbackId Fallback resource ID if custom icon not found
     * @return Resource ID of the drawable or fallback
     */
    private fun getDrawableResourceId(resourceName: String, fallbackId: Int): Int {
        return try {
            // First try plugin package (where icons are located)
            val pluginResId = resources.getIdentifier(resourceName, "drawable", "com.example.voip_twilio_sdk")
            if (pluginResId != 0) {
                Log.d(TAG, "Found custom icon '$resourceName' in plugin package")
                return pluginResId
            }
            
            // Then try app package (allows app to override plugin icons)
            val appPackageName = packageName
            val appResId = resources.getIdentifier(resourceName, "drawable", appPackageName)
            if (appResId != 0) {
                Log.d(TAG, "Found custom icon '$resourceName' in app package")
                return appResId
            }
            
            // Fallback to system icon
            Log.d(TAG, "Custom icon '$resourceName' not found, using fallback system icon")
            fallbackId
        } catch (e: Exception) {
            Log.w(TAG, "Error getting drawable resource '$resourceName': ${e.message}, using fallback")
            fallbackId
        }
    }

    fun updateCallState(
        contactPhone: String? = null,
        muted: Boolean? = null,
        speakerOn: Boolean? = null,
        startTime: Long? = null,
        showTimer: Boolean = true
    ) {
        if (contactPhone != null) {
            callContactPhone = contactPhone
        }
        if (muted != null) {
            isMuted = muted
        }
        if (speakerOn != null) {
            isSpeakerOn = speakerOn
        }
        if (startTime != null) {
            callStartTime = startTime
        }
        
        val notification = createCallStyleNotification(showTimer = showTimer)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, " Call notification updated: contact=$callContactPhone, muted=$isMuted, speaker=$isSpeakerOn")
        } catch (e: Exception) {
            Log.e(TAG, " Error updating notification: ${e.message}", e)
        }
    }
}

