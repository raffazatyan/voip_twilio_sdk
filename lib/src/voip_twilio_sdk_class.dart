import 'dart:async';

import 'models/call_event.dart';
import 'models/call_options.dart';
import 'twilio_voice_channel_service.dart';

/// Main class for interacting with Twilio Voice SDK
///
/// This is the public API for the voip_twilio_sdk plugin.
/// Use this class to make and manage VoIP calls.
///
/// You can get an instance by calling [VoipTwilioSdk.instance].
///
/// Example:
/// ```dart
/// final sdk = VoipTwilioSdk.instance;
/// // SDK is automatically initialized - no need to call initialize()
///
/// sdk.callEventsStream.listen((event) {
///   print('Call event: $event');
/// });
///
/// await sdk.connect(CallOptions(
///   from: 'client:username',
///   to: '+1234567890',
///   token: 'your_token',
/// ));
/// ```
class VoipTwilioSdk {
  static VoipTwilioSdk? _instance;
  final TwilioVoiceChannelService _service = TwilioVoiceChannelService();

  /// Private constructor
  VoipTwilioSdk._() {
    // Initialize automatically in constructor
    _service.initTwilioVoiceChannel();
  }

  /// Gets the singleton instance of [VoipTwilioSdk]
  ///
  /// The SDK is automatically initialized when the instance is first accessed.
  /// No manual initialization is required - just use the instance and start calling methods!
  static VoipTwilioSdk get instance {
    _instance ??= VoipTwilioSdk._();
    return _instance!;
  }

  /// Connect a call with the given options
  ///
  /// [callOptions] contains the call configuration including:
  /// - `from`: Your Twilio client identifier
  /// - `to`: Phone number or client identifier to call
  /// - `token`: Twilio access token
  ///
  /// Throws [PlatformException] if the call cannot be initiated.
  Future<void> connect(CallOptions callOptions) async {
    return _service.connect(callOptions);
  }

  /// Hang up the current call
  ///
  /// Ends the active call and plays a busy tone.
  Future<void> hangUp() async {
    return _service.hangUp();
  }

  /// Toggle mute state
  ///
  /// [isMuted] - true to mute, false to unmute
  Future<void> toggleMute({bool isMuted = false}) async {
    return _service.toggleMute(isMuted: isMuted);
  }

  /// Toggle speaker state
  ///
  /// [isSpeakerOn] - true for speaker, false for receiver (earpiece)
  Future<void> toggleSpeaker({bool isSpeakerOn = false}) async {
    return _service.toggleSpeaker(isSpeakerOn: isSpeakerOn);
  }

  /// Send DTMF digits during a call
  ///
  /// [digits] - Single digit string (0-9, *, #)
  /// Use this for IVR systems that require digit input.
  Future<void> sendDigits(String digits) async {
    return _service.sendDigits(digits);
  }

  /// Get the current call SID
  ///
  /// Returns the Twilio Call SID if a call is active, null otherwise.
  /// The SID can be used for call tracking and logging.
  Future<String?> getSid() async {
    return _service.getSid();
  }

  /// Stream of call events
  ///
  /// Listen to this stream to receive real-time call events:
  /// - `ringing` - Call is ringing
  /// - `connected` - Call is connected
  /// - `mute` / `unmute` - Microphone state changed
  /// - `speakerOn` / `speakerOff` - Speaker state changed
  /// - `callEnded` - Call ended
  /// - `declined` - Call was declined
  Stream<CallEvent> get callEventsStream => _service.callEventsStream;
}
