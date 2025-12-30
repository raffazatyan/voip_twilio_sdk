package com.example.voip_twilio_sdk

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin

class VoipTwilioSdkPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        TwilioVoiceChannelHandler.getInstance().setup(binding.binaryMessenger, context)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        TwilioVoiceChannelHandler.getInstance().cleanup()
    }
}

