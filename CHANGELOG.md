## 1.1.0

- **iOS**: Implemented flexible sample rate handling to prevent crashes on different devices and simulators
  - Replaced hardcoded sample rates (44100.0) with dynamic detection from AVAudioSession
  - Uses AVAudioSession.sampleRate as primary source, falls back to 48000.0 if invalid
  - Improved error handling with guard let statements instead of force unwraps
  - Added logging for sample rate debugging
  - Prevents crashes on iOS simulators and different device configurations

## 1.0.3 - 1.0.11 

- Added detailed iOS setup instructions for enabling Background Modes in Xcode
- Added troubleshooting section for Background Modes configuration
- Improved documentation with step-by-step guide for "Voice over IP" capability

## 1.0.2

- Made all protocol methods in extensions public (`FlutterStreamHandler`, `CXProviderDelegate`, `CallDelegate`)
- Fixed Swift visibility requirements for protocol conformance

## 1.0.1

- Added `VoipTwilioSdkPlugin` class for iOS to enable automatic plugin registration via `GeneratedPluginRegistrant`
- Made `TwilioVoiceChannelHandler` public with public `setup()` and `cleanup()` methods
- Added `@objc` support to `VoipTwilioSdkPlugin` for Objective-C compatibility
- Plugin now works automatically for all users without manual AppDelegate/SceneDelegate setup

## 1.0.0

- Initial version.
