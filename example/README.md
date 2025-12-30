# VoIP Twilio SDK Example

This is a complete example Flutter application demonstrating how to use the `voip_twilio_sdk` plugin.

## Features Demonstrated

- 📞 Making VoIP calls with Twilio
- 🔇 Mute/unmute functionality
- 🔊 Speaker/receiver toggle
- 🔢 DTMF keypad for sending digits
- 📊 Real-time call event monitoring
- 📱 Call status display
- 📝 Event logging

## How to Run

1. **Navigate to the example directory:**
   ```bash
   cd example
   ```

2. **Get dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

## Configuration

Before making calls, you need to:

1. **Get a Twilio Access Token** from your backend server
   - The token must include Voice grants
   - Never generate tokens in the app!

2. **Enter your configuration:**
   - **Twilio Access Token**: Paste your token in the token field
   - **From**: Your client identifier (e.g., `current_client`)
   - **To**: Phone number or client identifier to call (e.g., `+1234567890`)

3. **Make a call:**
   - Tap the "Make Call" button
   - Wait for the call to connect
   - Use the controls to mute, toggle speaker, send digits, or hang up

## UI Overview

- **Configuration Section**: Enter your Twilio token and call details
- **Call Status**: Shows current call state and SID
- **Call Controls**: Mute, speaker, and hang up buttons (visible during active calls)
- **DTMF Keypad**: Send digits during calls (for IVR systems)
- **Event Log**: Real-time log of all call events

## Notes

- The example app demonstrates all features of the plugin
- Events are logged in real-time for debugging
- Call SID is displayed when call connects
- All controls work both from the app and from Android notification

## Troubleshooting

If calls don't work:
- Verify your Twilio access token is valid
- Check that token includes Voice grants
- Ensure microphone permissions are granted
- Check the event log for error messages

