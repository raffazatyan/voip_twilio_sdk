import 'dart:async';

import 'package:flutter/services.dart';

import 'models/call_event.dart';
import 'models/call_options.dart';

/// Internal service for communicating with native Twilio Voice SDK via method channels
/// This class is not exported and should not be used directly.
/// Use [VoipTwilioSdk] instead.
class TwilioVoiceChannelService {
  final MethodChannel _methodChannel = const MethodChannel(
    'com.example.voip_twilio_sdk/twilio_voice',
  );

  final EventChannel _eventChannel = const EventChannel(
    'com.example.voip_twilio_sdk/twilio_voice_events',
  );

  late final Stream<CallEvent> _callEventsStream;

  TwilioVoiceChannelService();

  /// Initialize the Twilio Voice channel and set up event stream
  void initTwilioVoiceChannel() {
    _callEventsStream = _eventChannel.receiveBroadcastStream().map(
      (event) => CallEventExtension.fromNativeString(event as String),
    );
  }

  /// Connect a call with the given options
  Future<void> connect(CallOptions callOptions) async {
    try {
      await _methodChannel.invokeMethod('connect', {
        'from': callOptions.from,
        'to': callOptions.to,
        'token': callOptions.token,
      });
    } on PlatformException {
      // Handle error if needed
    }
  }

  /// Hang up the current call
  Future<void> hangUp() async {
    try {
      await _methodChannel.invokeMethod('hangUp');
    } on PlatformException {
      // Handle error if needed
    }
  }

  /// Toggle mute state
  Future<void> toggleMute({bool isMuted = false}) async {
    try {
      await _methodChannel.invokeMethod('toggleMute', {'isMuted': isMuted});
    } on PlatformException {
      // Handle error if needed
    }
  }

  /// Toggle speaker state
  Future<void> toggleSpeaker({bool isSpeakerOn = false}) async {
    try {
      await _methodChannel.invokeMethod('toggleSpeaker', {
        'isSpeakerOn': isSpeakerOn,
      });
    } on PlatformException {
      // Handle error if needed
    }
  }

  /// Send DTMF digits during a call
  Future<void> sendDigits(String digits) async {
    try {
      await _methodChannel.invokeMethod('sendDigits', {'digits': digits});
    } on PlatformException {
      // Handle error if needed
    }
  }

  /// Get the current call SID
  Future<String?> getSid() async {
    try {
      final result = await _methodChannel.invokeMethod('getSid');
      return result as String?;
    } on PlatformException {
      return null;
    }
  }

  /// Stream of call events
  Stream<CallEvent> get callEventsStream => _callEventsStream;
}
