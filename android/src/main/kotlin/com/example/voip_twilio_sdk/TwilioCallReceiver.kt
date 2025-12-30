package com.example.voip_twilio_sdk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BroadcastReceiver for handling call actions from notifications
 * 
 * This receiver handles:
 * - Hang up action
 * - Toggle mute action
 * - Toggle speaker action
 */
class TwilioCallReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "TwilioCallReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        Log.d(TAG, "Received broadcast action: $action")

        when {
            action == "com.example.voip_twilio_sdk.CALL_HANG_UP" -> {
                Log.d(TAG, "Hang up action received")
                TwilioVoiceChannelHandler.getInstance().handleHangUpFromNotification()
            }
            action == "com.example.voip_twilio_sdk.CALL_TOGGLE_MUTE" -> {
                Log.d(TAG, "Toggle mute action received")
                TwilioVoiceChannelHandler.getInstance().handleToggleMuteFromNotification()
            }
            action == "com.example.voip_twilio_sdk.CALL_TOGGLE_SPEAKER" -> {
                Log.d(TAG, "Toggle speaker action received")
                TwilioVoiceChannelHandler.getInstance().handleToggleSpeakerFromNotification()
            }
            else -> {
                Log.w(TAG, "Unknown action: $action")
            }
        }
    }
}

