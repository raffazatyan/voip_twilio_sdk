import 'package:flutter/material.dart';
import 'package:voip_twilio_sdk/voip_twilio_sdk.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoIP Twilio SDK Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CallScreen(),
    );
  }
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late VoipTwilioSdk _sdk;

  // Form controllers
  final _tokenController = TextEditingController();
  final _fromController = TextEditingController(text: 'current_client');
  final _toController = TextEditingController();

  // Call state
  CallEvent? _currentEvent;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  String? _callSid;
  bool _isCallActive = false;

  // Event log
  final List<String> _eventLog = [];

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  void _initializeService() {
    _sdk = VoipTwilioSdk.instance;
    // SDK is automatically initialized - no need to call initialize()

    // Listen to call events
    _sdk.callEventsStream.listen((event) {
      setState(() {
        _currentEvent = event;
        _addToLog('Event: ${event.name}');

        // Update UI based on events
        switch (event) {
          case CallEvent.mute:
            _isMuted = true;
            break;
          case CallEvent.unmute:
            _isMuted = false;
            break;
          case CallEvent.speakerOn:
            _isSpeakerOn = true;
            break;
          case CallEvent.speakerOff:
            _isSpeakerOn = false;
            break;
          case CallEvent.connected:
            _isCallActive = true;
            // Get call SID when connected
            _sdk.getSid().then((sid) {
              if (sid != null) {
                setState(() {
                  _callSid = sid;
                  _addToLog('Call SID: $sid');
                });
              }
            });
            break;
          case CallEvent.callEnded:
          case CallEvent.declined:
            _isCallActive = false;
            _callSid = null;
            break;
          default:
            break;
        }
      });
    });
  }

  void _addToLog(String message) {
    setState(() {
      _eventLog.insert(
        0,
        '${DateTime.now().toString().substring(11, 19)}: $message',
      );
      if (_eventLog.length > 50) {
        _eventLog.removeLast();
      }
    });
  }

  Future<void> _makeCall() async {
    if (_tokenController.text.isEmpty) {
      _showSnackBar('Please enter Twilio access token');
      return;
    }

    if (_fromController.text.isEmpty) {
      _showSnackBar('Please enter "from" identifier');
      return;
    }

    if (_toController.text.isEmpty) {
      _showSnackBar('Please enter "to" phone number or identifier');
      return;
    }

    final callOptions = CallOptions(
      from: _fromController.text.trim(),
      to: _toController.text.trim(),
      token: _tokenController.text.trim(),
    );

    try {
      _addToLog('Initiating call...');
      await _sdk.connect(callOptions);
      _addToLog('Call initiated successfully');
      _showSnackBar('📞 Call initiated');
    } catch (e) {
      _addToLog('Error: $e');
      _showSnackBar('❌ Error: $e');
    }
  }

  Future<void> _toggleMute() async {
    try {
      await _sdk.toggleMute(isMuted: !_isMuted);
      _addToLog('Mute toggled: ${!_isMuted}');
    } catch (e) {
      _addToLog('Error toggling mute: $e');
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _toggleSpeaker() async {
    try {
      await _sdk.toggleSpeaker(isSpeakerOn: !_isSpeakerOn);
      _addToLog('Speaker toggled: ${!_isSpeakerOn}');
    } catch (e) {
      _addToLog('Error toggling speaker: $e');
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _sendDigit(String digit) async {
    try {
      await _sdk.sendDigits(digit);
      _addToLog('DTMF digit sent: $digit');
      _showSnackBar('Digit sent: $digit');
    } catch (e) {
      _addToLog('Error sending digit: $e');
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _hangUp() async {
    try {
      await _sdk.hangUp();
      _addToLog('Hang up called');
      _showSnackBar('📴 Call ended');
    } catch (e) {
      _addToLog('Error hanging up: $e');
      _showSnackBar('Error: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📞 VoIP Twilio SDK Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Configuration Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configuration',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tokenController,
                      decoration: const InputDecoration(
                        labelText: 'Twilio Access Token',
                        hintText: 'Enter your Twilio access token',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key),
                      ),
                      obscureText: true,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fromController,
                      decoration: const InputDecoration(
                        labelText: 'From (Client Identifier)',
                        hintText: 'e.g., current_client',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _toController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'To (Phone Number or Client)',
                        hintText: 'e.g., +1234567890',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isCallActive ? null : _makeCall,
                        icon: const Icon(Icons.call),
                        label: const Text('Make Call'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Call Status Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Call Status',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _getStatusIcon(),
                          size: 32,
                          color: _getStatusColor(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getStatusText(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_callSid != null)
                                Text(
                                  'SID: ${_callSid!.substring(0, 20)}...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Call Controls Section
            if (_isCallActive) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Call Controls',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Mute Button
                          Column(
                            children: [
                              IconButton(
                                onPressed: _toggleMute,
                                icon: Icon(
                                  _isMuted ? Icons.mic_off : Icons.mic,
                                  size: 32,
                                ),
                                color: _isMuted ? Colors.red : Colors.blue,
                                style: IconButton.styleFrom(
                                  backgroundColor: _isMuted
                                      ? Colors.red[50]
                                      : Colors.blue[50],
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isMuted ? 'Unmute' : 'Mute',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),

                          // Speaker Button
                          Column(
                            children: [
                              IconButton(
                                onPressed: _toggleSpeaker,
                                icon: Icon(
                                  _isSpeakerOn
                                      ? Icons.volume_up
                                      : Icons.volume_down,
                                  size: 32,
                                ),
                                color: _isSpeakerOn ? Colors.blue : Colors.grey,
                                style: IconButton.styleFrom(
                                  backgroundColor: _isSpeakerOn
                                      ? Colors.blue[50]
                                      : Colors.grey[50],
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSpeakerOn ? 'Speaker' : 'Receiver',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),

                          // Hang Up Button
                          Column(
                            children: [
                              IconButton(
                                onPressed: _hangUp,
                                icon: const Icon(Icons.call_end, size: 32),
                                color: Colors.white,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Hang Up',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // DTMF Keypad
                      const Text(
                        'DTMF Keypad',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final digits = [
                            '1',
                            '2',
                            '3',
                            '4',
                            '5',
                            '6',
                            '7',
                            '8',
                            '9',
                            '*',
                            '0',
                            '#',
                          ];
                          return ElevatedButton(
                            onPressed: () => _sendDigit(digits[index]),
                            child: Text(
                              digits[index],
                              style: const TextStyle(fontSize: 24),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Event Log Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Event Log',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_eventLog.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _eventLog.clear();
                              });
                            },
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: _eventLog.isEmpty
                          ? const Center(
                              child: Text(
                                'No events yet',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              reverse: false,
                              itemCount: _eventLog.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    _eventLog[index],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Info Section
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'How to get Twilio Access Token',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Generate token on your backend server\n'
                      '2. Token must include Voice grants\n'
                      '3. Never generate tokens in the app!\n'
                      '4. See README.md for more details',
                      style: TextStyle(color: Colors.blue[900]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (_currentEvent) {
      case CallEvent.connected:
        return Icons.call;
      case CallEvent.ringing:
        return Icons.phone_in_talk;
      case CallEvent.callEnded:
        return Icons.call_end;
      case CallEvent.declined:
        return Icons.call_missed;
      default:
        return Icons.phone_disabled;
    }
  }

  Color _getStatusColor() {
    switch (_currentEvent) {
      case CallEvent.connected:
        return Colors.green;
      case CallEvent.ringing:
        return Colors.orange;
      case CallEvent.callEnded:
      case CallEvent.declined:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText() {
    if (_currentEvent == null) {
      return 'No active call';
    }

    switch (_currentEvent!) {
      case CallEvent.connected:
        return 'Call Connected';
      case CallEvent.ringing:
        return 'Ringing...';
      case CallEvent.mute:
        return 'Muted';
      case CallEvent.unmute:
        return 'Unmuted';
      case CallEvent.speakerOn:
        return 'Speaker On';
      case CallEvent.speakerOff:
        return 'Receiver Mode';
      case CallEvent.callEnded:
        return 'Call Ended';
      case CallEvent.declined:
        return 'Call Declined';
      default:
        return 'Status: ${_currentEvent!.name}';
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }
}
