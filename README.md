# 📞 voip_twilio_sdk

![RAFFAZATYAN.DEV Package Publisher](https://github.com/raffazatyan/voip_twilio_sdk/raw/main/doc/images/package-banner.png)

A comprehensive Flutter plugin for Twilio Voice SDK integration. This plugin provides complete VoIP calling capabilities using Twilio Voice SDK **without requiring any native code implementation**.

## ✨ Features

### Core Features
- 📲 Make and receive VoIP calls using Twilio Voice SDK
- 🔇 Mute/unmute calls
- 🔊 Toggle speaker/receiver mode
- 🔢 Send DTMF digits during calls
- 📡 Real-time call event stream
- 🔄 Background call support
- 📊 Call state management
- 🆔 Get call SID for tracking

### 🎯 Unique Features (Not Available in Other Packages)

#### 🔔 **GSM Ringback Tone**
- **Automatic ringback tone generation** when call is ringing
- Standard GSM specification: 425 Hz sine wave
- Pattern: 1 second tone ON, 3 seconds tone OFF, repeating
- Works seamlessly with VoIP audio routing
- No external audio files required - pure audio synthesis

#### 📱 **Custom Android Notification UI**
- **Full-featured call notification** in Android notification center
- **Interactive actions directly from notification**:
  - 🔇 Mute/Unmute button
  - 🔊 Speaker/Receiver toggle button
  - 📞 Hang up button
- **Call timer** showing call duration
- **CallStyle notification** (Android 12+) with native look and feel
- **Foreground service** support for background calls
- **Proximity sensor integration** - automatically turns off screen when phone is near face

#### 🎵 **Busy Tone**
- **Automatic busy tone** (3 short beeps) when call ends
- Standard phone system tone
- 425 Hz frequency, 0.2s beeps with 0.1s pauses

#### 🎚️ **Advanced Audio Management**
- **Smart audio routing** - automatically handles speaker/receiver switching
- **Proximity sensor support** - screen turns off during calls when phone is near face
- **Audio focus management** - proper handling of other audio sources
- **Bluetooth headset support**

## 📦 Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  voip_twilio_sdk: ^1.0.4
```

Then run:

```bash
flutter pub get
```

### 🤖 Android Setup

#### 1. Permissions

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
    
    <!-- Optional: For better battery optimization handling -->
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
</manifest>
```

#### 2. Gradle Configuration

The Twilio Voice SDK will be automatically included via Gradle. The plugin uses:
- **Twilio Voice Android SDK 6.3.0**
- **Minimum SDK**: 21 (Android 5.0)
- **Target SDK**: 34

#### 3. Notification Channel

The plugin automatically creates a notification channel for call notifications. No additional setup required!

### 🍎 iOS Setup

#### 1. Info.plist Configuration

Add the following to your `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to microphone to make voice calls</string>
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

#### 2. Enable Background Modes in Xcode

**⚠️ IMPORTANT**: You must enable "Voice over IP" in Background Modes in Xcode, otherwise calls will not work!

1. Open your project in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. Select your **Runner** target in the project navigator

3. Go to the **Signing & Capabilities** tab

4. Click **+ Capability** button

5. Search for and add **Background Modes**

6. In the Background Modes section, check the following options:
   - ✅ **Voice over IP** (required for VoIP calls)

![Background Modes Configuration](https://github.com/raffazatyan/voip_twilio_sdk/raw/main/doc/images/ios-background-modes.png)

**Note**: If you don't enable "Voice over IP" in Background Modes, the plugin will not be able to make or receive calls. This is a requirement for VoIP functionality on iOS.

#### 3. Pod Installation

Run the following command in your project root:

```bash
cd ios
pod install
cd ..
```

The plugin uses:
- **Twilio Voice iOS SDK 6.0+**
- **Minimum iOS**: 12.0
- **CallKit integration** for native iOS call experience

**Troubleshooting**: If calls are not working, verify that:
- ✅ "Voice over IP" is enabled in Background Modes (see step 2 above)
- ✅ Microphone permission is granted
- ✅ `UIBackgroundModes` includes `voip` and `audio` in Info.plist

## 🎮 Example App

A complete example application is included in the `example` directory. To run it:

```bash
cd example
flutter pub get
flutter run
```

The example app includes:
- 📝 Form fields for entering Twilio token and call details
- 📊 Real-time call status display
- 🎛️ Full call controls (mute, speaker, hang up)
- 🔢 DTMF keypad for sending digits
- 📋 Event log for debugging

**Quick Start**: Just enter your Twilio access token, "from" and "to" fields, then tap "Make Call"!

See [example/README.md](example/README.md) for more details.

## 🚀 Usage

### 1. Get SDK Instance

```dart
import 'package:voip_twilio_sdk/voip_twilio_sdk.dart';

// Get SDK instance (singleton) - initialization happens automatically!
final sdk = VoipTwilioSdk.instance;
```

**Note**: The SDK uses a **singleton pattern** - use `VoipTwilioSdk.instance` to get the shared instance. It's **automatically initialized** when first accessed. No need to call `initialize()` - it's done for you! 🎉

### 2. Set Up Event Listener

**Important**: Set up the event listener **before** making calls:

```dart
sdk.callEventsStream.listen((event) {
  switch (event) {
    case CallEvent.connected:
      print('✅ Call connected');
      // Call is now active
      break;
    case CallEvent.ringing:
      print('📞 Call ringing - ringback tone playing');
      // Ringback tone is automatically playing
      break;
    case CallEvent.mute:
      print('🔇 Microphone muted');
      break;
    case CallEvent.unmute:
      print('🔊 Microphone unmuted');
      break;
    case CallEvent.speakerOn:
      print('🔊 Speaker enabled');
      break;
    case CallEvent.speakerOff:
      print('📱 Receiver mode (speaker off)');
      break;
    case CallEvent.callEnded:
      print('📴 Call ended - busy tone played');
      // Busy tone (3 beeps) automatically played
      break;
    case CallEvent.declined:
      print('❌ Call declined');
      break;
    case CallEvent.fallback:
      print('⚠️ Unknown event received');
      break;
  }
});
```

### 3. Make a Call

```dart
// Prepare call options
final callOptions = CallOptions(
  from: 'current_client',  // Your Twilio client identifier
  to: '+1234567890',        // Phone number or client identifier to call
  token: 'your_twilio_access_token',  // Twilio access token
);

// Initiate the call
try {
  await sdk.connect(callOptions);
  print('📞 Call initiated');
} catch (e) {
  print('❌ Error starting call: $e');
}
```

**What happens when you call `connect()`:**
1. 🔔 Ringback tone starts playing automatically
2. 📱 Android: Custom notification appears with call controls
3. 🍎 iOS: Native CallKit interface appears
4. 📡 Call events start streaming

### 4. Control Active Calls

#### Mute/Unmute

```dart
// Mute the call
await sdk.toggleMute(isMuted: true);

// Unmute the call
await sdk.toggleMute(isMuted: false);
```

**Android**: The notification button updates automatically to show current mute state.

#### Toggle Speaker/Receiver

```dart
// Enable speaker
await sdk.toggleSpeaker(isSpeakerOn: true);

// Switch to receiver (earpiece)
await sdk.toggleSpeaker(isSpeakerOn: false);
```

**Android**: 
- When speaker is OFF, proximity sensor activates (screen turns off when phone is near face)
- When speaker is ON, proximity sensor deactivates
- Notification button shows current speaker state

#### Send DTMF Digits

```dart
// Send a single digit (e.g., for IVR systems)
await sdk.sendDigits('1');

// Send multiple digits one by one
for (var digit in '1234'.split('')) {
  await sdk.sendDigits(digit);
  await Future.delayed(Duration(milliseconds: 200)); // Small delay between digits
}
```

#### Get Call Information

```dart
// Get the Twilio Call SID
final callSid = await sdk.getSid();
if (callSid != null) {
  print('Call SID: $callSid');
  // Use SID for call tracking, logging, etc.
}
```

#### Hang Up

```dart
// End the call
await sdk.hangUp();
```

**What happens when you call `hangUp()`:**
1. 🔔 Busy tone (3 short beeps) plays automatically
2. 📱 Notification is dismissed
3. 🔄 All call state is reset
4. 📴 `callEnded` event is sent

## 📱 Android Notification Features

### Custom Call Notification

The plugin creates a **full-featured call notification** on Android with:

- **CallStyle notification** (Android 12+) - Native Android call UI
- **Call timer** - Shows call duration in real-time
- **Contact information** - Displays the phone number being called
- **Interactive buttons**:
  - 🔇 **Mute/Unmute** - Toggle microphone
  - 🔊 **Speaker/Receiver** - Toggle audio output
  - 📞 **Hang Up** - End the call

### Using Notification Actions

Users can control calls directly from the notification without opening the app:

```dart
// The notification automatically handles these actions:
// - Mute/Unmute button press
// - Speaker/Receiver toggle
// - Hang up button press

// Your app receives events through callEventsStream:
sdk.callEventsStream.listen((event) {
  if (event == CallEvent.mute) {
    // User pressed mute from notification
    // Update your UI accordingly
  }
});
```

### Foreground Service

The plugin uses a **foreground service** to ensure:
- ✅ Calls continue in background
- ✅ Microphone access works in background
- ✅ Notification stays visible
- ✅ System doesn't kill the call process

## 🎵 Audio Features

### Ringback Tone

The plugin automatically generates and plays a **GSM-standard ringback tone** when a call is ringing:

- **Frequency**: 425 Hz sine wave
- **Pattern**: 1 second tone ON, 3 seconds tone OFF (repeating)
- **Audio routing**: Properly routed through voice call stream
- **Bluetooth compatible**: Works with Bluetooth headsets
- **Automatic**: Starts when call is ringing, stops when connected

**No configuration needed** - it just works! 🎉

### Busy Tone

When a call ends (either by hanging up or being declined), the plugin automatically plays a **busy tone**:

- **Pattern**: 3 short beeps (0.2s each) with 0.1s pauses
- **Frequency**: 425 Hz (same as ringback for consistency)
- **Duration**: ~0.8 seconds total

This provides audio feedback that the call has ended, just like traditional phone systems.

### Proximity Sensor (Android)

The plugin automatically manages the proximity sensor:

- **When speaker is OFF**: Sensor activates, screen turns off when phone is near face
- **When speaker is ON**: Sensor deactivates, screen stays on
- **Automatic cleanup**: Sensor stops when call ends

This provides a natural calling experience similar to native phone apps.

## 📊 Complete Example

Here's a complete example showing all features:

```dart
import 'package:flutter/material.dart';
import 'package:voip_twilio_sdk/voip_twilio_sdk.dart';

class CallScreen extends StatefulWidget {
  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late VoipTwilioSdk _sdk;
  CallEvent? _currentEvent;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  String? _callSid;

  @override
  void initState() {
    super.initState();
    _initializeSdk();
  }

  void _initializeSdk() {
    _sdk = VoipTwilioSdk.instance;
    // SDK is automatically initialized - no need to call initialize()
    
    // Listen to call events
    _sdk.callEventsStream.listen((event) {
      setState(() {
        _currentEvent = event;
        
        // Update UI based on events
        if (event == CallEvent.mute) {
          _isMuted = true;
        } else if (event == CallEvent.unmute) {
          _isMuted = false;
        } else if (event == CallEvent.speakerOn) {
          _isSpeakerOn = true;
        } else if (event == CallEvent.speakerOff) {
          _isSpeakerOn = false;
        } else if (event == CallEvent.connected) {
          // Get call SID when connected
          _sdk.getSid().then((sid) {
            setState(() {
              _callSid = sid;
            });
          });
        }
      });
    });
  }

  Future<void> _makeCall() async {
    final callOptions = CallOptions(
      from: 'current_client', 		
      to: '+1234567890',
      token: 'your_twilio_access_token',
    );
    
    try {
      await _sdk.connect(callOptions);
      print('📞 Call initiated');
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  Future<void> _toggleMute() async {
    await _sdk.toggleMute(isMuted: !_isMuted);
  }

  Future<void> _toggleSpeaker() async {
    await _sdk.toggleSpeaker(isSpeakerOn: !_isSpeakerOn);
  }

  Future<void> _hangUp() async {
    await _sdk.hangUp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('VoIP Call')),
      body: Column(
        children: [
          // Call status
          Text('Status: ${_currentEvent?.name ?? "Idle"}'),
          if (_callSid != null) Text('Call SID: $_callSid'),
          
          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute button
              IconButton(
                icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                onPressed: _toggleMute,
              ),
              
              // Speaker button
              IconButton(
                icon: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_down),
                onPressed: _toggleSpeaker,
              ),
              
              // Hang up button
              IconButton(
                icon: Icon(Icons.call_end, color: Colors.red),
                onPressed: _hangUp,
              ),
            ],
          ),
          
          // Make call button
          ElevatedButton(
            onPressed: _makeCall,
            child: Text('Make Call'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up if needed
    super.dispose();
  }
}
```

## 🎯 Call Events Reference

| Event | Description | When It Occurs |
|-------|-------------|----------------|
| `ringing` | Call is ringing | When the call starts ringing (ringback tone plays) |
| `connected` | Call is connected | When the call is successfully connected |
| `mute` | Microphone muted | When mute is enabled (from app or notification) |
| `unmute` | Microphone unmuted | When mute is disabled (from app or notification) |
| `speakerOn` | Speaker enabled | When speaker mode is enabled |
| `speakerOff` | Speaker disabled | When receiver mode is enabled (speaker off) |
| `callEnded` | Call ended | When call ends normally (busy tone plays) |
| `declined` | Call declined | When call is declined (603 response) |
| `fallback` | Unknown event | For any unrecognized event |

## 🔧 Advanced Configuration

### Handling Notification Actions (Android)

If you want to handle notification button presses in your app, you can set up broadcast receivers. However, the plugin automatically handles these internally and sends events through `callEventsStream`.

### Custom Notification (Future Enhancement)

Currently, the notification uses system icons. For custom icons, you would need to:
1. Add your icons to `android/app/src/main/res/drawable/`
2. Modify the plugin's notification code (requires plugin modification)

### Error Handling

Always wrap call operations in try-catch:

```dart
try {
  await sdk.connect(callOptions);
} on PlatformException catch (e) {
  print('Platform error: ${e.code} - ${e.message}');
} catch (e) {
  print('Error: $e');
}
```

## 📋 Requirements

- **Flutter**: 3.0.0 or higher
- **Dart**: 3.10.3 or higher
- **Android**: 
  - minSdkVersion: 21 (Android 5.0)
  - compileSdkVersion: 34
- **iOS**: 12.0 or higher
- **Twilio Account**: With Voice SDK access enabled

## 🔑 Getting Twilio Access Token

You need to generate a Twilio access token on your **backend server**. The token must include Voice grants.

### Example Token Generation (Node.js)

```javascript
const twilio = require('twilio');

const AccessToken = twilio.jwt.AccessToken;
const VoiceGrant = AccessToken.VoiceGrant;

function generateToken(identity) {
  const voiceGrant = new VoiceGrant({
    outgoingApplicationSid: 'your_twiml_app_sid',
    incomingAllow: true, // Allow incoming calls
  });

  const token = new AccessToken(
    'your_account_sid',
    'your_api_key_sid',
    'your_api_key_secret',
    { identity: identity }
  );

  token.addGrant(voiceGrant);
  return token.toJwt();
}
```

**Important Security Notes:**
- ⚠️ **Never** generate tokens in your Flutter app
- ✅ Always generate tokens on your backend server
- ✅ Tokens should be short-lived (1 hour recommended)
- ✅ Use Twilio API Keys, not Account SID/Auth Token

See [Twilio Access Token Documentation](https://www.twilio.com/docs/voice/quickstart) for more details.

## 🆚 Comparison with Other Packages

### Why Choose voip_twilio_sdk?

| Feature | voip_twilio_sdk | Other Packages |
|---------|----------------|----------------|
| 🔔 Ringback Tone | ✅ Automatic GSM tone | ❌ Not available |
| 📱 Custom Android Notification | ✅ Full CallStyle with actions | ⚠️ Basic only |
| 🎵 Busy Tone | ✅ Automatic on hangup | ❌ Not available |
| 📳 Proximity Sensor | ✅ Automatic management | ❌ Not available |
| 🔇 Notification Mute Button | ✅ Works from notification | ❌ App only |
| 🔊 Notification Speaker Toggle | ✅ Works from notification | ❌ App only |
| ⏱️ Call Timer in Notification | ✅ Real-time duration | ⚠️ Limited support |
| 🎚️ Advanced Audio Routing | ✅ Smart switching | ⚠️ Basic only |

## 🐛 Troubleshooting

### Android Issues

#### Call doesn't work in background
- ✅ Ensure `FOREGROUND_SERVICE_MICROPHONE` permission is granted
- ✅ Check that notification channel is created (automatic)
- ✅ Verify app is not in battery optimization mode

#### No ringback tone
- ✅ Check audio permissions are granted
- ✅ Verify call is actually ringing (check events)
- ✅ Check device volume is not muted

#### Notification actions don't work
- ✅ Ensure app has notification permission (Android 13+)
- ✅ Check that notification channel allows actions
- ✅ Verify app is not killed by system

### iOS Issues

#### Calls don't work at all
- ✅ **CRITICAL**: Verify "Voice over IP" is enabled in Background Modes in Xcode (see iOS Setup step 2)
- ✅ Check that `UIBackgroundModes` includes `voip` and `audio` in Info.plist
- ✅ Verify microphone permission is granted
- ✅ Ensure Twilio Voice SDK is properly installed via CocoaPods

#### CallKit doesn't appear
- ✅ Verify "Voice over IP" is enabled in Background Modes in Xcode
- ✅ Check that `UIBackgroundModes` includes `voip` and `audio` in Info.plist
- ✅ Check microphone permission is granted
- ✅ Ensure Twilio Voice SDK is properly installed via CocoaPods

#### No ringback tone
- ✅ Check audio session is properly configured
- ✅ Verify call is actually ringing
- ✅ Check device volume

## 📚 Additional Resources

- [Twilio Voice Documentation](https://www.twilio.com/docs/voice)
- [Twilio Voice Android SDK](https://www.twilio.com/docs/voice/sdks/android)
- [Twilio Voice iOS SDK](https://www.twilio.com/docs/voice/sdks/ios)
- [Flutter Plugin Development](https://flutter.dev/docs/development/packages-and-plugins/developing-packages)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Twilio Voice SDK](https://www.twilio.com/voice)
- Uses [Flutter](https://flutter.dev) framework

---

**Made with ❤️ for the Flutter community**
