## 1.0.1

- Added `VoipTwilioSdkPlugin` class for iOS to enable automatic plugin registration via `GeneratedPluginRegistrant`
- Made `TwilioVoiceChannelHandler` public with public `setup()` and `cleanup()` methods
- Added `@objc` support to `VoipTwilioSdkPlugin` for Objective-C compatibility
- Plugin now works automatically for all users without manual AppDelegate/SceneDelegate setup

## 1.0.0

- Initial version.
