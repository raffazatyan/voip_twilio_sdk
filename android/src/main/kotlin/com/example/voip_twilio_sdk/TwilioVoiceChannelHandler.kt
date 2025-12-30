
package com.example.voip_twilio_sdk

import android.app.PendingIntent
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import androidx.core.content.ContextCompat
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.twilio.voice.Call
import com.twilio.voice.CallException
import com.twilio.voice.ConnectOptions
import com.twilio.voice.Voice
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.HashMap

class TwilioVoiceChannelHandler private constructor() {

    companion object {
        private const val TAG = "TwilioVoiceChannel"
        private const val METHOD_CHANNEL_NAME = "com.example.voip_twilio_sdk/twilio_voice"
        private const val EVENT_CHANNEL_NAME = "com.example.voip_twilio_sdk/twilio_voice_events"

        @Volatile
        private var instance: TwilioVoiceChannelHandler? = null

        fun getInstance(): TwilioVoiceChannelHandler {
            return instance ?: synchronized(this) {
                instance ?: TwilioVoiceChannelHandler().also { instance = it }
            }
        }
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var activeCall: Call? = null
    private var audioManager: AudioManager? = null
    private var sensorManager: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var powerManager: PowerManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var isMuted = false
    private var isSpeakerOn = false
    private var pendingMuteState: Boolean? = null
    private var pendingSpeakerState: Boolean? = null
    private var callContactPhone: String? = null
    private var callStartTime: Long = 0
    private var isProximitySensorActive = false
    private var ringbackAudioTrack: AudioTrack? = null
    private var ringbackThread: Thread? = null
    private var isRingbackPlaying = false
    private var busyToneAudioTrack: AudioTrack? = null
    private var busyToneThread: Thread? = null

    fun setup(messenger: io.flutter.plugin.common.BinaryMessenger, applicationContext: Context) {
        this.context = applicationContext.applicationContext
        this.audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        this.sensorManager = context?.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        this.powerManager = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
        this.proximitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)

        // Notification channel is now created by TwilioCallService
        // createCallNotificationChannel()

        // Setup method channel
        methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
        methodChannel?.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        // Setup event channel
        eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                Log.d(TAG, "Event channel listener attached")
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                Log.d(TAG, "Event channel listener cancelled")
            }
        })

        Log.d(TAG, " Twilio Voice channel setup complete")
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "Received method call: ${call.method}")

        try {
            when (call.method) {
                "connect" -> handleConnect(call, result)
                "hangUp" -> handleHangUp(result)
                "toggleMute" -> handleToggleMute(call, result)
                "toggleSpeaker" -> handleToggleSpeaker(call, result)
                "sendDigits" -> handleSendDigits(call, result)
                "getSid" -> handleGetSid(result)
                else -> {
                    Log.w(TAG, " Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, " Error handling method call ${call.method}: ${e.message}", e)
            result.error("METHOD_CALL_ERROR", "Error handling ${call.method}: ${e.message}", null)
        }
    }

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>

            // Extract individual fields from arguments
            val from = args?.get("from") as? String
            val to = args?.get("to") as? String
            val token = args?.get("token") as? String

            if (from.isNullOrEmpty() || to.isNullOrEmpty() || token.isNullOrEmpty()) {
                result.error("INVALID_OPTIONS", "from, to, and token are required", null)
                return
            }

            // Store call options for later use (excluding token, which will be used separately)
            // Token is stored separately because Twilio SDK requires it as a separate parameter
            // in ConnectOptions.Builder(accessToken) constructor, not in params
            val params = HashMap<String, String>()
            
            // iOS SDK automatically adds "client:" prefix to "From" parameter
            // We need to do the same for Android to match iOS behavior
            val fromWithPrefix = if (!from.startsWith("client:")) {
                "client:$from"
            } else {
                from
            }
            params["From"] = fromWithPrefix
            Log.d(TAG, "Added client: prefix to From parameter: $fromWithPrefix")
            
            params["To"] = to
            
            // Save "To" phone number for notification
            callContactPhone = to
            Log.d(TAG, "Saved contact phone for notification: $to")

            val connectOptions = ConnectOptions.Builder(token)
                .params(params)
                .build()

            val context = this.context
            if (context == null) {
                result.error("NO_CONTEXT", "Context is null", null)
                return
            }

            // Check RECORD_AUDIO permission before starting call
            if (ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                Log.w(TAG, " RECORD_AUDIO permission not granted, call may fail in background")
                // Continue anyway - Twilio SDK may handle this, but we should still try
            }

            // Start foreground service for microphone access in background
            // Service will create CallStyle notification
            startTwilioCallService(to, isMuted, isSpeakerOn)

            // Notification is now handled by TwilioCallService
            // showCallNotification(showTimer = false)

            // Activate proximity sensor for call (only if speaker is off)
            if (!isSpeakerOn) {
                startProximitySensor()
            }

            // Create Twilio call
            activeCall = Voice.connect(context, connectOptions, callListener)
            
            Log.d(TAG, " Call initiated")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, " Error connecting call: ${e.message}", e)
            result.error("CONNECT_ERROR", "Failed to connect call: ${e.message}", null)
        }
    }

    private fun handleHangUp(result: MethodChannel.Result) {
        try {
            stopRingback()
            // Play busy tone (3 short beeps) when hanging up
            playBusyTone()
            
            activeCall?.disconnect()
            activeCall = null
            isMuted = false
            // Reset speaker to receiver (off) when call ends
            if (isSpeakerOn) {
                setSpeaker(false)
            }
            isSpeakerOn = false
            // Notification is now handled by TwilioCallService, no need to cancel separately
            // cancelCallNotification()
            callContactPhone = null
            callStartTime = 0L
            
            // Stop proximity sensor when call is hung up
            stopProximitySensor()
            
            // Stop foreground service
            stopTwilioCallService()
            
            Log.d(TAG, " Call disconnected")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, " Error hanging up: ${e.message}", e)
            result.error("HANGUP_ERROR", "Failed to hang up: ${e.message}", null)
        }
    }

    private fun handleToggleMute(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>
            val isMuted = args?.get("isMuted") as? Boolean ?: false

            // Check if call is connected (callStartTime > 0 means call is connected)
            val isCallConnected = callStartTime > 0 && activeCall != null

            if (isCallConnected) {
                // Call is connected, apply immediately
                activeCall?.mute(isMuted)
                this.isMuted = isMuted
                Log.d(TAG, " Microphone ${if (isMuted) "muted" else "unmuted"}")
                sendEvent(if (isMuted) "mute" else "unmute")
                // Update service notification
                updateTwilioCallService(muted = isMuted)
            } else {
                // Call not connected yet, store pending state
                pendingMuteState = isMuted
                this.isMuted = isMuted
                Log.d(TAG, " Microphone state saved (pending): ${if (isMuted) "muted" else "unmuted"} (will apply when call connects)")
                sendEvent(if (isMuted) "mute" else "unmute")
                // Update service notification with new mute state even if call is not connected yet
                updateTwilioCallService(muted = isMuted)
            }
            
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, " Error toggling mute: ${e.message}", e)
            result.error("MUTE_ERROR", "Failed to toggle mute: ${e.message}", null)
        }
    }

    private fun handleToggleSpeaker(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>
            val isSpeakerOn = args?.get("isSpeakerOn") as? Boolean ?: false

            val audioManager = this.audioManager
            if (audioManager == null) {
                result.error("NO_AUDIO_MANAGER", "AudioManager is null", null)
                return
            }

            // Check if call is connected (callStartTime > 0 means call is connected)
            val isCallConnected = callStartTime > 0 && activeCall != null

            if (isCallConnected) {
                // Call is connected, apply immediately
                setSpeaker(isSpeakerOn)
                this.isSpeakerOn = isSpeakerOn
                Log.d(TAG, " Speaker ${if (isSpeakerOn) "enabled" else "disabled"}")
                sendEvent(if (isSpeakerOn) "speakerOn" else "speakerOff")
                
                // Manage proximity sensor based on speaker state
                if (isSpeakerOn) {
                    // Stop proximity sensor when speaker is on
                    stopProximitySensor()
                } else {
                    // Start proximity sensor when speaker is off (receiver mode)
                    startProximitySensor()
                }
                // Update service notification with new speaker state
                updateTwilioCallService(speakerOn = isSpeakerOn)
            } else {
                // Call not connected yet - apply to Android AudioManager immediately
                // and store pending state for when call connects (Twilio SDK will take over)
                setSpeaker(isSpeakerOn)
                pendingSpeakerState = isSpeakerOn
                this.isSpeakerOn = isSpeakerOn
                Log.d(TAG, " Speaker ${if (isSpeakerOn) "enabled" else "disabled"} via Android AudioManager (pending for Twilio when call connects)")
                sendEvent(if (isSpeakerOn) "speakerOn" else "speakerOff")
                
                // Manage proximity sensor based on speaker state
                if (isSpeakerOn) {
                    // Stop proximity sensor when speaker is on
                    stopProximitySensor()
                } else {
                    // Start proximity sensor when speaker is off (receiver mode)
                    startProximitySensor()
                }
                // Update service notification with new speaker state even if call is not connected yet
                updateTwilioCallService(speakerOn = isSpeakerOn)
            }
            
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, " Error toggling speaker: ${e.message}", e)
            result.error("SPEAKER_ERROR", "Failed to toggle speaker: ${e.message}", null)
        }
    }

    private fun setSpeaker(on: Boolean) {
        val context = this.context ?: return
        val audioManager = this.audioManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

            val speaker = devices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }

            if (on && speaker != null) {
                audioManager.setCommunicationDevice(speaker)
            } else {
                audioManager.clearCommunicationDevice()
            }
        } else {
            // Fallback to deprecated API for older Android versions
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = on
        }
    }

    private fun isSpeakerOn(): Boolean {
        val audioManager = this.audioManager ?: return false
        
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.communicationDevice?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        } else {
            // Fallback to deprecated API for older Android versions
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn
        }
    }

    private fun handleSendDigits(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *>
            val digit = args?.get("digits") as? String

            if (digit.isNullOrEmpty()) {
                result.error("INVALID_DIGITS", "Digit is required", null)
                return
            }

            // Send only a single digit at a time
            val twilioCall = activeCall
            if (twilioCall == null) {
                result.error("NO_CALL", "No active call", null)
                return
            }

            twilioCall.sendDigits(digit)
            Log.d(TAG, " Digit sent: $digit")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, " Error sending digit: ${e.message}", e)
            result.error("SEND_DIGITS_ERROR", "Failed to send digit: ${e.message}", null)
        }
    }

    private fun handleGetSid(result: MethodChannel.Result) {
        try {
            val sid = activeCall?.sid
            Log.d(TAG, " Call SID: $sid")
            result.success(sid)
        } catch (e: Exception) {
            Log.e(TAG, " Error getting SID: ${e.message}", e)
            result.error("GET_SID_ERROR", "Failed to get SID: ${e.message}", null)
        }
    }

    private inner class TwilioCallListener : Call.Listener {
        override fun onConnectFailure(call: Call, callException: CallException) {
            Log.e(TAG, " Call connect failure: ${callException.message}")
            stopRingback()
            val errorMessage = callException.message ?: ""
            // Check if call was declined (603 Decline)
            val isDeclined = errorMessage.contains("Decline", ignoreCase = true) ||
                    errorMessage.contains("603", ignoreCase = true)
            
            if (isDeclined) {
                sendEvent("declined")
            } else {
                sendEvent("callEnded")
            }
            activeCall = null
            isMuted = false
            // Reset speaker to receiver (off) when call fails
            if (isSpeakerOn) {
                setSpeaker(false)
            }
            isSpeakerOn = false
            pendingMuteState = null
            pendingSpeakerState = null
        }

        override fun onRinging(call: Call) {
            Log.d(TAG, " Call ringing")
            startRingback()
            sendEvent("ringing")
        }

        override fun onConnected(call: Call) {
            Log.d(TAG, " Call connected")
            stopRingback()
            // Save call start time for chronometer when call is successfully connected
            callStartTime = System.currentTimeMillis()
            
            // Apply pending mute state if it was set before connection
            pendingMuteState?.let { muteState ->
                try {
                    call.mute(muteState)
                    isMuted = muteState
                    Log.d(TAG, " Applied pending mute state: ${if (muteState) "muted" else "unmuted"}")
                } catch (e: Exception) {
                    Log.e(TAG, " Error applying pending mute state: ${e.message}", e)
                }
                pendingMuteState = null
            }
            
            // Apply pending speaker state if it was set before connection
            // Note: We already applied it to Android AudioManager before connection,
            // but now that Twilio SDK is connected, we need to ensure it's synced
            pendingSpeakerState?.let { speakerState ->
                val audioManager = this@TwilioVoiceChannelHandler.audioManager
                if (audioManager != null) {
                    // Post to main thread handler to apply after a short delay
                    // This ensures Twilio SDK has fully initialized audio
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        try {
                            // Set audio mode for voice call before setting speaker
                            audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION)
                            // Re-apply speaker state now that Twilio SDK is connected
                            setSpeaker(speakerState)
                            isSpeakerOn = speakerState
                            Log.d(TAG, " Synced speaker state with Twilio SDK: ${if (speakerState) "enabled" else "disabled"}")
                            
                            // Manage proximity sensor based on speaker state
                            if (speakerState) {
                                // Stop proximity sensor when speaker is on
                                stopProximitySensor()
                            } else {
                                // Start proximity sensor when speaker is off (receiver mode)
                                startProximitySensor()
                            }
                            
                            // Update service notification with new speaker state
                            updateTwilioCallService(speakerOn = speakerState)
                        } catch (e: Exception) {
                            Log.e(TAG, " Error syncing speaker state with Twilio SDK: ${e.message}", e)
                        }
                    }, 200) // 200ms delay to ensure audio is ready
                }
                pendingSpeakerState = null
            }
            
            // Update foreground service notification with call state
            // Notification is now handled by TwilioCallService
            updateTwilioCallService(
                contactPhone = callContactPhone,
                muted = isMuted,
                speakerOn = isSpeakerOn,
                startTime = callStartTime,
                showTimer = true
            )
            
            // Old notification code - now handled by service
            // showCallNotification(showTimer = true)
            
            sendEvent("connected")
        }

        override fun onReconnecting(call: Call, callException: CallException) {
            Log.d(TAG, " Call reconnecting: ${callException.message}")
        }

        override fun onReconnected(call: Call) {
            Log.d(TAG, " Call reconnected")
        }

        override fun onDisconnected(call: Call, callException: CallException?) {
            Log.d(TAG, " Call disconnected: ${callException?.message ?: "normal disconnect"}")
            stopRingback()
            val errorMessage = callException?.message ?: ""
            // Check if call was declined (603 Decline)
            val isDeclined = errorMessage.contains("Decline", ignoreCase = true) ||
                    errorMessage.contains("603", ignoreCase = true)
            
            if (isDeclined) {
                sendEvent("declined")
            } else {
                sendEvent("callEnded")
            }
            activeCall = null
            isMuted = false
            // Reset speaker to receiver (off) when call ends
            if (isSpeakerOn) {
                setSpeaker(false)
            }
            isSpeakerOn = false
            pendingMuteState = null
            pendingSpeakerState = null
            // Notification is now handled by TwilioCallService, no need to cancel separately
            // cancelCallNotification()
            callContactPhone = null
            callStartTime = 0L
            
            // Stop proximity sensor when call ends
            stopProximitySensor()
            
            // Stop foreground service
            stopTwilioCallService()
        }
    }

    private val callListener: Call.Listener = TwilioCallListener()

    private fun sendEvent(eventName: String) {
        try {
            eventSink?.success(eventName)
            Log.d(TAG, " Event sent: $eventName")
        } catch (e: Exception) {
            Log.e(TAG, " Error sending event: ${e.message}", e)
        }
    }

    // Notification channel creation removed - now handled by TwilioCallService
    // Channel is created in TwilioCallService.onCreate()

    // Notification creation methods removed - now handled by TwilioCallService
    // All notification logic has been moved to TwilioCallService to support foreground service

    fun handleHangUpFromNotification() {
        if (activeCall == null) {
            Log.w(TAG, " Hang up from notification: No active call")
            return
        }
        try {
            stopRingback()
            // Play busy tone when hanging up from notification
            playBusyTone()
            activeCall?.disconnect()
            activeCall = null
            isMuted = false
            // Reset speaker to receiver (off) when call ends
            if (isSpeakerOn) {
                setSpeaker(false)
            }
            isSpeakerOn = false
            pendingMuteState = null
            pendingSpeakerState = null
            // Notification is now handled by TwilioCallService, no need to cancel separately
            // cancelCallNotification()
            callContactPhone = null
            callStartTime = 0L
            
            // Stop proximity sensor when call is hung up
            stopProximitySensor()
            
            // Stop foreground service
            stopTwilioCallService()
            
            sendEvent("callEnded")
            Log.d(TAG, " Call disconnected from notification")
        } catch (e: Exception) {
            Log.e(TAG, " Error hanging up from notification: ${e.message}", e)
        }
    }

    fun handleToggleMuteFromNotification() {
        if (activeCall == null) {
            Log.w(TAG, " Toggle mute from notification: No active call")
            return
        }
        try {
            val newMuteState = !isMuted
            
            // Check if call is connected (callStartTime > 0 means call is connected)
            val isCallConnected = callStartTime > 0 && activeCall != null
            
            if (isCallConnected) {
                // Call is connected, apply immediately
                activeCall?.mute(newMuteState)
                isMuted = newMuteState
                Log.d(TAG, " Microphone ${if (isMuted) "muted" else "unmuted"} from notification")
            } else {
                // Call not connected yet, store pending state
                pendingMuteState = newMuteState
                isMuted = newMuteState
                Log.d(TAG, " Microphone state saved (pending) from notification: ${if (isMuted) "muted" else "unmuted"}")
            }
            
            sendEvent(if (isMuted) "mute" else "unmute")
            // Update service notification with new state
            updateTwilioCallService(muted = isMuted)
        } catch (e: Exception) {
            Log.e(TAG, " Error toggling mute from notification: ${e.message}", e)
        }
    }

    fun handleToggleSpeakerFromNotification() {
        if (activeCall == null) {
            Log.w(TAG, " Toggle speaker from notification: No active call")
            return
        }
        try {
            val audioManager = this.audioManager
            if (audioManager == null) {
                Log.e(TAG, " AudioManager is null")
                return
            }
            
            val newSpeakerState = !isSpeakerOn
            
            // Check if call is connected (callStartTime > 0 means call is connected)
            val isCallConnected = callStartTime > 0 && activeCall != null
            
            if (isCallConnected) {
                // Call is connected, apply immediately
                setSpeaker(newSpeakerState)
                isSpeakerOn = newSpeakerState
                Log.d(TAG, " Speaker ${if (isSpeakerOn) "enabled" else "disabled"} from notification")
            } else {
                // Call not connected yet - apply to Android AudioManager immediately
                // and store pending state for when call connects
                setSpeaker(newSpeakerState)
                pendingSpeakerState = newSpeakerState
                isSpeakerOn = newSpeakerState
                Log.d(TAG, " Speaker ${if (isSpeakerOn) "enabled" else "disabled"} via Android AudioManager from notification (pending for Twilio)")
            }
            
            sendEvent(if (isSpeakerOn) "speakerOn" else "speakerOff")
            
            // Manage proximity sensor based on speaker state
            if (isSpeakerOn) {
                // Stop proximity sensor when speaker is on
                stopProximitySensor()
            } else {
                // Start proximity sensor when speaker is off (receiver mode)
                startProximitySensor()
            }
            
            // Update service notification with new state
            updateTwilioCallService(speakerOn = isSpeakerOn)
        } catch (e: Exception) {
            Log.e(TAG, " Error toggling speaker from notification: ${e.message}", e)
        }
    }

    fun cleanup() {
        try {
            stopRingback()
            stopBusyTone()
            activeCall?.disconnect()
            activeCall = null
            eventSink = null
            isMuted = false
            // Reset speaker to receiver (off) during cleanup
            if (isSpeakerOn) {
                setSpeaker(false)
            }
            isSpeakerOn = false
            pendingMuteState = null
            pendingSpeakerState = null
            // Notification is now handled by TwilioCallService, no need to cancel separately
            // cancelCallNotification()
            callContactPhone = null
            callStartTime = 0L
            
            // Stop proximity sensor during cleanup
            stopProximitySensor()
            
            // Stop foreground service during cleanup
            stopTwilioCallService()
            
            Log.d(TAG, " Twilio Voice channel cleaned up")
        } catch (e: Exception) {
            Log.e(TAG, " Error during cleanup: ${e.message}", e)
        }
    }

    private fun startTwilioCallService(contactPhone: String, muted: Boolean, speakerOn: Boolean) {
        val context = this.context ?: run {
            Log.e(TAG, "Cannot start Twilio call service: context is null")
            return
        }

        try {
            val serviceIntent = Intent(context, TwilioCallService::class.java).apply {
                putExtra("call_contact_phone", contactPhone)
                putExtra("is_muted", muted)
                putExtra("is_speaker_on", speakerOn)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            Log.d(TAG, " Twilio call service started")
        } catch (e: Exception) {
            Log.e(TAG, " Error starting Twilio call service: ${e.message}", e)
        }
    }

    private fun stopTwilioCallService() {
        val context = this.context ?: run {
            Log.e(TAG, "Cannot stop Twilio call service: context is null")
            return
        }

        try {
            val serviceIntent = Intent(context, TwilioCallService::class.java)
            context.stopService(serviceIntent)
            Log.d(TAG, " Twilio call service stopped")
        } catch (e: Exception) {
            Log.e(TAG, " Error stopping Twilio call service: ${e.message}", e)
        }
    }

    private fun updateTwilioCallService(
        contactPhone: String? = null,
        muted: Boolean? = null,
        speakerOn: Boolean? = null,
        startTime: Long? = null,
        showTimer: Boolean = true
    ) {
        try {
            TwilioCallService.getInstance()?.updateCallState(
                contactPhone = contactPhone,
                muted = muted,
                speakerOn = speakerOn,
                startTime = startTime,
                showTimer = showTimer
            )
        } catch (e: Exception) {
            Log.e(TAG, " Error updating Twilio call service: ${e.message}", e)
        }
    }

    private val proximitySensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            if (event?.sensor?.type == Sensor.TYPE_PROXIMITY) {
                val distance = event.values[0]
                val maxRange = event.sensor.maximumRange
                
                // If distance is less than max range, object is close (near face)
                val isNear = distance < maxRange
                
                if (isNear) {
                    // Turn off screen when phone is near face
                    turnScreenOff()
                } else {
                    // Turn on screen when phone is away from face
                    turnScreenOn()
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
            // Not needed for proximity sensor
        }
    }

    private fun startProximitySensor() {
        // Don't start if speaker is on
        if (isSpeakerOn) {
            Log.d(TAG, " Proximity sensor not started - speaker is on")
            return
        }
        
        if (isProximitySensorActive) {
            return
        }
        
        proximitySensor?.let { sensor ->
            try {
                sensorManager?.registerListener(
                    proximitySensorListener,
                    sensor,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
                isProximitySensorActive = true
                Log.d(TAG, " Proximity sensor activated")
            } catch (e: Exception) {
                Log.e(TAG, " Error starting proximity sensor: ${e.message}", e)
            }
        } ?: run {
            Log.w(TAG, " Proximity sensor not available on this device")
        }
    }

    private fun stopProximitySensor() {
        if (!isProximitySensorActive) {
            return
        }
        
        try {
            sensorManager?.unregisterListener(proximitySensorListener)
            isProximitySensorActive = false
            turnScreenOn() // Ensure screen is on when sensor stops
            Log.d(TAG, " Proximity sensor deactivated")
        } catch (e: Exception) {
            Log.e(TAG, " Error stopping proximity sensor: ${e.message}", e)
        }
    }

    private fun turnScreenOff() {
        try {
            if (wakeLock?.isHeld != true) {
                wakeLock = powerManager?.newWakeLock(
                    PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "VoipTwilioSdk:ProximityWakeLock"
                )
                wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes max
                Log.d(TAG, " Screen turned off (proximity)")
            }
        } catch (e: Exception) {
            Log.e(TAG, " Error turning screen off: ${e.message}", e)
        }
    }

    private fun turnScreenOn() {
        try {
            wakeLock?.takeIf { it.isHeld }?.apply {
                release()
                Log.d(TAG, " Screen turned on (proximity)")
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, " Error turning screen on: ${e.message}", e)
        }
    }

    /**
     * Starts GSM ringback tone generation.
     * 
     * GSM ringback tone specification:
     * - Frequency: 425 Hz sine wave
     * - Pattern: 1 second tone ON, 3 seconds tone OFF, repeating
     * - Stream: STREAM_VOICE_CALL (for VoIP calls, ensures proper audio routing)
     * 
     * Why STREAM_VOICE_CALL?
     * - VoIP calls use voice call stream for proper audio routing
     * - System correctly handles audio focus and routing
     * - Works correctly with Bluetooth headsets and speakerphone
     * - Prevents conflicts with music/notification streams
     */
    private fun startRingback() {
        try {
            val audioManager = this.audioManager ?: run {
                Log.e(TAG, " AudioManager is null, cannot start ringback")
                return
            }

            // Stop any existing ringback first
            stopRingback()

            // Set audio mode for voice call
            audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION)

            // GSM ringback tone parameters
            val sampleRate = 44100 // Standard sample rate
            val frequency = 425.0 // Hz - GSM ringback tone frequency
            val toneDurationMs = 1000L // 1 second ON
            val pauseDurationMs = 3000L // 3 seconds OFF
            val samplesPerTone = (sampleRate * toneDurationMs / 1000).toInt()
            val samplesPerPause = (sampleRate * pauseDurationMs / 1000).toInt()

            // Generate sine wave samples for one tone cycle (1 sec ON)
            val toneSamples = ShortArray(samplesPerTone)
            for (i in toneSamples.indices) {
                val angle = 2.0 * Math.PI * i * frequency / sampleRate
                toneSamples[i] = (Math.sin(angle) * Short.MAX_VALUE).toInt().toShort()
            }

            // Generate silence samples for pause (3 sec OFF)
            val pauseSamples = ShortArray(samplesPerPause)

            // Calculate buffer size for one complete cycle (tone + pause)
            val bufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            if (bufferSize == AudioTrack.ERROR_BAD_VALUE || bufferSize == AudioTrack.ERROR) {
                Log.e(TAG, " Invalid buffer size for AudioTrack")
                return
            }

            // Create AudioTrack for voice call stream
            ringbackAudioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            ringbackAudioTrack?.let { track ->
                // Set volume to maximum (normalized 0.0 to 1.0)
                // For mono audio, both left and right channels use the same value
                track.setVolume(1.0f)

                // Start playback
                track.play()
                isRingbackPlaying = true

                Log.d(TAG, " GSM ringback tone started (425 Hz, 1s ON / 3s OFF)")

                // Play ringback tone in a separate thread to avoid blocking
                ringbackThread = Thread {
                    try {
                        while (isRingbackPlaying && !Thread.currentThread().isInterrupted) {
                            // Write tone (1 second)
                            track.write(toneSamples, 0, toneSamples.size)

                            // Check if we should continue
                            if (!isRingbackPlaying) break

                            // Write pause/silence (3 seconds)
                            track.write(pauseSamples, 0, pauseSamples.size)

                            // Check if we should continue
                            if (!isRingbackPlaying) break
                        }
                    } catch (e: Exception) {
                        if (isRingbackPlaying) {
                            Log.e(TAG, " Error in ringback playback thread: ${e.message}", e)
                        }
                    }
                }.apply {
                    name = "RingbackThread"
                    start()
                }
            } ?: run {
                Log.e(TAG, " Failed to create AudioTrack for ringback")
            }
        } catch (e: Exception) {
            Log.e(TAG, " Error starting ringback: ${e.message}", e)
            // Clean up on error
            stopRingback()
        }
    }

    /**
     * Stops GSM ringback tone generation and releases all resources.
     * 
     * This method:
     * - Stops the playback thread
     * - Stops and releases AudioTrack
     * - Resets audio mode to normal
     * - Ensures no resource leaks
     */
    private fun stopRingback() {
        try {
            // Signal thread to stop
            isRingbackPlaying = false

            // Interrupt and wait for thread to finish
            ringbackThread?.interrupt()
            ringbackThread?.join(500) // Wait max 500ms for thread to finish
            ringbackThread = null

            // Stop and release AudioTrack
            ringbackAudioTrack?.let { track ->
                try {
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        track.stop()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, " Error stopping AudioTrack: ${e.message}")
                }
                try {
                    track.release()
                } catch (e: Exception) {
                    Log.w(TAG, " Error releasing AudioTrack: ${e.message}")
                }
            }
            ringbackAudioTrack = null

            // Reset audio mode to normal
            audioManager?.setMode(AudioManager.MODE_NORMAL)

            Log.d(TAG, " GSM ringback tone stopped")
        } catch (e: Exception) {
            Log.e(TAG, " Error stopping ringback: ${e.message}", e)
        }
    }

    /**
     * Plays busy tone (3 short beeps) when call is ended.
     * 
     * Busy tone specification:
     * - Frequency: 425 Hz (same as ringback for consistency)
     * - Pattern: 3 short beeps (0.2s each) with 0.1s pauses between them
     * - Total duration: ~0.8 seconds
     * - Stream: STREAM_VOICE_CALL (for VoIP calls)
     * 
     * This is the standard "call ended" tone used in phone systems.
     */
    private fun playBusyTone() {
        try {
            val audioManager = this.audioManager ?: run {
                Log.e(TAG, " AudioManager is null, cannot play busy tone")
                return
            }

            // Stop any existing busy tone first
            stopBusyTone()

            // Set audio mode for voice call
            audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION)

            // Busy tone parameters
            val sampleRate = 44100
            val frequency = 425.0 // Hz - same as ringback
            val beepDurationMs = 200L // 0.2 seconds per beep
            val pauseDurationMs = 100L // 0.1 seconds pause between beeps
            val beepCount = 3 // 3 beeps total

            val samplesPerBeep = (sampleRate * beepDurationMs / 1000).toInt()
            val samplesPerPause = (sampleRate * pauseDurationMs / 1000).toInt()

            // Generate sine wave samples for one beep (0.2 sec)
            val beepSamples = ShortArray(samplesPerBeep)
            for (i in beepSamples.indices) {
                val angle = 2.0 * Math.PI * i * frequency / sampleRate
                beepSamples[i] = (Math.sin(angle) * Short.MAX_VALUE).toInt().toShort()
            }

            // Generate silence samples for pause (0.1 sec)
            val pauseSamples = ShortArray(samplesPerPause)

            // Calculate buffer size
            val bufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            if (bufferSize == AudioTrack.ERROR_BAD_VALUE || bufferSize == AudioTrack.ERROR) {
                Log.e(TAG, " Invalid buffer size for busy tone AudioTrack")
                return
            }

            // Create AudioTrack for voice call stream
            busyToneAudioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(sampleRate)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            busyToneAudioTrack?.let { track ->
                // Set volume to maximum
                track.setVolume(1.0f)

                // Start playback
                track.play()

                Log.d(TAG, " Busy tone started (3 beeps: 425 Hz, 0.2s ON / 0.1s OFF)")

                // Play busy tone in a separate thread
                busyToneThread = Thread {
                    try {
                        // Play 3 beeps with pauses between them
                        for (i in 0 until beepCount) {
                            // Write beep
                            track.write(beepSamples, 0, beepSamples.size)

                            // Write pause (except after last beep)
                            if (i < beepCount - 1) {
                                track.write(pauseSamples, 0, pauseSamples.size)
                            }
                        }

                        // Wait for playback to finish (all beeps + pauses)
                        Thread.sleep((beepDurationMs * beepCount + pauseDurationMs * (beepCount - 1)))

                        // Stop and release
                        stopBusyTone()
                    } catch (e: InterruptedException) {
                        // Thread was interrupted, stop playback
                        Log.d(TAG, "Busy tone thread interrupted")
                        stopBusyTone()
                    } catch (e: Exception) {
                        Log.e(TAG, " Error in busy tone playback thread: ${e.message}", e)
                        stopBusyTone()
                    }
                }.apply {
                    name = "BusyToneThread"
                    start()
                }
            } ?: run {
                Log.e(TAG, " Failed to create AudioTrack for busy tone")
            }
        } catch (e: Exception) {
            Log.e(TAG, " Error starting busy tone: ${e.message}", e)
            stopBusyTone()
        }
    }

    /**
     * Stops busy tone playback and releases all resources.
     */
    private fun stopBusyTone() {
        try {
            // Interrupt and wait for thread to finish
            busyToneThread?.interrupt()
            busyToneThread?.join(300) // Wait max 300ms for thread to finish
            busyToneThread = null

            // Stop and release AudioTrack
            busyToneAudioTrack?.let { track ->
                try {
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        track.stop()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, " Error stopping busy tone AudioTrack: ${e.message}")
                }
                try {
                    track.release()
                } catch (e: Exception) {
                    Log.w(TAG, " Error releasing busy tone AudioTrack: ${e.message}")
                }
            }
            busyToneAudioTrack = null

            Log.d(TAG, " Busy tone stopped")
        } catch (e: Exception) {
            Log.e(TAG, " Error stopping busy tone: ${e.message}", e)
        }
    }
}

