/// Options for making a Twilio Voice call
class CallOptions {
  /// The caller identifier (usually a client name)
  final String from;

  /// The callee phone number or identifier
  final String to;

  /// Twilio access token for authentication
  final String token;

  const CallOptions({
    required this.from,
    required this.to,
    required this.token,
  });
}

