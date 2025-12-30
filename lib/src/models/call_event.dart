/// Call events returned from native Twilio Voice SDK
enum CallEvent {
  /// Call has been successfully connected
  connected,

  /// Call is ringing
  ringing,

  /// Microphone has been muted
  mute,

  /// Microphone has been unmuted
  unmute,

  /// Speaker has been turned on
  speakerOn,

  /// Speaker has been turned off
  speakerOff,

  /// Call has ended
  callEnded,

  /// Call was declined
  declined,

  /// Fallback event for unknown events
  fallback,
}

/// Extension to convert from native string to enum
extension CallEventExtension on CallEvent {
  /// Convert native string to enum
  static CallEvent fromNativeString(String event) {
    switch (event.toLowerCase()) {
      case 'connected':
        return CallEvent.connected;
      case 'ringing':
        return CallEvent.ringing;
      case 'mute':
        return CallEvent.mute;
      case 'unmute':
        return CallEvent.unmute;
      case 'speakeron':
        return CallEvent.speakerOn;
      case 'speakeroff':
        return CallEvent.speakerOff;
      case 'callended':
        return CallEvent.callEnded;
      case 'declined':
        return CallEvent.declined;
      default:
        return CallEvent.fallback;
    }
  }
}
