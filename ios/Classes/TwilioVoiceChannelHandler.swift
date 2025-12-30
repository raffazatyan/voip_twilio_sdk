import AVFoundation
import CallKit
import Flutter
import Foundation
import TwilioVoice
import os.log

public class TwilioVoiceChannelHandler: NSObject {
    public static let shared = TwilioVoiceChannelHandler()
    
    private let logger = Logger(subsystem: "com.example.voip_twilio_sdk", category: "TwilioVoiceChannel")
    
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    private var activeCall: Call?
    private var callUUID: UUID?
    
    private var isMuted = false
    private var isSpeakerOn = false
    private var pendingMuteState: Bool?
    private var pendingSpeakerState: Bool?
    
    private var callKitProvider: CXProvider?
    private var callKitCallController: CXCallController?
    private var callKitCompletionCallback: ((Bool) -> Void)?
    
    private var audioDevice: DefaultAudioDevice = DefaultAudioDevice()
    
    private var isHandlingAudioRouteChange = false
    
    // GSM ringback tone properties
    private var ringbackEngine: AVAudioEngine?
    private var ringbackPlayerNode: AVAudioPlayerNode?
    private var isRingbackPlaying = false
    
    // Busy tone properties (3 short beeps on hangup)
    private var busyToneEngine: AVAudioEngine?
    private var busyTonePlayerNode: AVAudioPlayerNode?
    private var isBusyTonePlaying = false
    
    private override init() {
        super.init()
        setupCallKit()
        setupAudioRouteChangeObserver()
    }
    
    public func setup(with messenger: FlutterBinaryMessenger) {
        // Skip if already configured
        guard methodChannel == nil else {
            return
        }
        
        methodChannel = FlutterMethodChannel(
            name: "com.example.voip_twilio_sdk/twilio_voice",
            binaryMessenger: messenger
        )
        
        methodChannel?.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
        
        eventChannel = FlutterEventChannel(
            name: "com.example.voip_twilio_sdk/twilio_voice_events",
            binaryMessenger: messenger
        )
        
        eventChannel?.setStreamHandler(self)
        
        logger.info(" Twilio Voice channel setup complete")
    }
    
    private func setupCallKit() {
        let configuration = CXProviderConfiguration(localizedName: "VoIP Call")
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic, .phoneNumber]
        configuration.includesCallsInRecents = true
        
        callKitProvider = CXProvider(configuration: configuration)
        callKitCallController = CXCallController()
        
        callKitProvider?.setDelegate(self, queue: nil)
    }
    
    private func setupAudioRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioRouteChange(notification: Notification) {
        // Skip if we're currently handling a route change ourselves
        guard !isHandlingAudioRouteChange, activeCall != nil else {
            return
        }
        
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        // Handle route changes that are user-initiated (e.g., from Dynamic Island)
        // .override is used when overrideOutputAudioPort is called (from Dynamic Island or native UI)
        // .newDeviceAvailable/.oldDeviceUnavailable for device changes
        // .categoryChange for category changes
        let isUserInitiated = reason == .override || 
                              reason == .newDeviceAvailable || 
                              reason == .oldDeviceUnavailable || 
                              reason == .categoryChange
        
        guard isUserInitiated else {
            logger.info(" Audio route change ignored - reason: \(reason.rawValue)")
            return
        }
        
        // If ringback is playing, we need to restart it after route change
        // because AVAudioEngine might get disconnected from the audio session
        let wasRingbackPlaying = isRingbackPlaying
        
        // Check route change with retry mechanism to ensure we catch the change
        self.checkAudioRouteWithRetry(reason: reason, attempt: 1, maxAttempts: 3, wasRingbackPlaying: wasRingbackPlaying)
    }
    
    private func checkAudioRouteWithRetry(reason: AVAudioSession.RouteChangeReason, attempt: Int, maxAttempts: Int, wasRingbackPlaying: Bool = false) {
        guard activeCall != nil else {
            return
        }
        
        let delay = Double(attempt) * 0.1 // Increasing delay: 0.1s, 0.2s, 0.3s
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.activeCall != nil else {
                return
            }
            
            let session = AVAudioSession.sharedInstance()
            let currentRoute = session.currentRoute
            
            // Check if speaker is currently active
            // When speaker is on, output port type is .builtInSpeaker
            // When speaker is off (receiver), output port type is .builtInReceiver
            let isSpeakerActive = currentRoute.outputs.contains { output in
                output.portType == .builtInSpeaker
            }
            
            // Log detailed route information for debugging
            let outputPorts = currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
            self.logger.info("🔊 Audio route check (attempt \(attempt)/\(maxAttempts)) - reason: \(reason.rawValue), outputs: [\(outputPorts)], speaker active: \(isSpeakerActive), stored: \(self.isSpeakerOn)")
            
            // Only send event if state actually changed
            if isSpeakerActive != self.isSpeakerOn {
                self.isSpeakerOn = isSpeakerActive
                self.logger.info(" Audio route changed: Speaker \(isSpeakerActive ? "enabled" : "disabled") (from Dynamic Island/native UI)")
                self.sendEvent(isSpeakerActive ? "speakerOn" : "speakerOff")
                
                // If ringback was playing before route change, restart it after route change completes
                // This fixes the issue where ringback stops playing when toggling speaker/receiver
                // We restart after a short delay to ensure the audio route change has fully completed
                if wasRingbackPlaying {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self = self, self.activeCall != nil else { return }
                        // Only restart if call is still ringing (not connected yet)
                        if self.activeCall?.state != .connected {
                            self.logger.info(" Restarting ringback after audio route change")
                            self.startRingback()
                        }
                    }
                }
            } else if attempt < maxAttempts {
                // If state hasn't changed yet, retry (route change might still be in progress)
                self.logger.info(" State unchanged, retrying... (attempt \(attempt)/\(maxAttempts))")
                self.checkAudioRouteWithRetry(reason: reason, attempt: attempt + 1, maxAttempts: maxAttempts, wasRingbackPlaying: wasRingbackPlaying)
            } else {
                self.logger.info(" Audio route change detected but state unchanged after \(maxAttempts) attempts (already \(isSpeakerActive ? "on" : "off"))")
                
                // If ringback was playing and route change completed (even if state didn't change),
                // restart it to ensure it continues playing on the new route
                if wasRingbackPlaying {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self = self, self.activeCall != nil else { return }
                        // Only restart if call is still ringing (not connected yet)
                        if self.activeCall?.state != .connected {
                            self.logger.info(" Restarting ringback after audio route change (state unchanged)")
                            self.startRingback()
                        }
                    }
                }
            }
        }
    }
    
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        logger.info("Received method call: \(call.method)")
        
        switch call.method {
        case "connect":
            handleConnect(call, result: result)
        case "hangUp":
            handleHangUp(result)
        case "toggleMute":
            handleToggleMute(call, result: result)
        case "toggleSpeaker":
            handleToggleSpeaker(call, result: result)
        case "sendDigits":
            handleSendDigits(call, result: result)
        case "getSid":
            handleGetSid(result)
        default:
            logger.warning(" Unknown method: \(call.method)")
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_OPTIONS", message: "Arguments are required", details: nil))
            return
        }
        
        // Extract individual fields from arguments
        guard let from = args["from"] as? String,
              let to = args["to"] as? String,
              let token = args["token"] as? String,
              !from.isEmpty,
              !to.isEmpty,
              !token.isEmpty else {
            result(FlutterError(code: "INVALID_OPTIONS", message: "from, to, and token are required", details: nil))
            return
        }
        
        // Create call UUID
        let uuid = UUID()
        callUUID = uuid
        
        // Create CallKit start call action
        let handle = CXHandle(type: .phoneNumber, value: to)
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: startCallAction)
        
        // Store call options for later use (excluding token, which will be stored separately)
        // Token is stored separately because Twilio SDK requires it as a separate parameter
        // in ConnectOptions(accessToken:) constructor, not in builder.params
        var callOptions: [String: String] = [:]
        
        // iOS SDK automatically adds "client:" prefix to "From" parameter
        // Ensure it's present
        let fromWithPrefix = from.hasPrefix("client:") ? from : "client:\(from)"
        callOptions["From"] = fromWithPrefix
        callOptions["To"] = to
        
        // Store call options and token for later use
        objc_setAssociatedObject(self, &AssociatedKeys.callOptions, callOptions, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &AssociatedKeys.accessToken, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        callKitCallController?.request(transaction) { [weak self] error in
            if let error = error {
                self?.logger.error("StartCallAction transaction request failed: \(error.localizedDescription)")
                result(FlutterError(code: "CONNECT_ERROR", message: error.localizedDescription, details: nil))
            } else {
                self?.logger.info(" StartCallAction transaction request successful")
                result(nil)
            }
        }
    }
    
    private func handleHangUp(_ result: @escaping FlutterResult) {
        stopRingback()
        // Play busy tone (3 short beeps) when hanging up
        playBusyTone()
        
        guard let uuid = callUUID else {
            // No active call - this is idempotent, so return success
            logger.info(" Hang up called but no active call exists")
            result(nil)
            return
        }
        
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callKitCallController?.request(transaction) { [weak self] error in
            if let error = error {
                self?.logger.error("EndCallAction transaction request failed: \(error.localizedDescription)")
                result(FlutterError(code: "HANGUP_ERROR", message: error.localizedDescription, details: nil))
            } else {
                self?.logger.info(" Call disconnected")
                result(nil)
            }
        }
    }
    
    private func handleToggleMute(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let isMuted = args["isMuted"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "isMuted is required", details: nil))
            return
        }
        
        guard let activeCall = activeCall else {
            // Call not created yet, store pending state
            pendingMuteState = isMuted
            self.isMuted = isMuted
            logger.info(" Microphone state saved (pending): \(isMuted ? "muted" : "unmuted") (will apply when call connects)")
            sendEvent(isMuted ? "mute" : "unmute")
            result(nil)
            return
        }
        
        // Check if call is connected
        let isCallConnected = activeCall.state == .connected
        
        if isCallConnected {
            // Call is connected, apply immediately
            activeCall.isMuted = isMuted
            self.isMuted = isMuted
            logger.info(" Microphone \(isMuted ? "muted" : "unmuted")")
            sendEvent(isMuted ? "mute" : "unmute")
        } else {
            // Call not connected yet, store pending state
            pendingMuteState = isMuted
            self.isMuted = isMuted
            logger.info(" Microphone state saved (pending): \(isMuted ? "muted" : "unmuted") (will apply when call connects)")
            sendEvent(isMuted ? "mute" : "unmute")
        }
        
        result(nil)
    }
    
    private func handleToggleSpeaker(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let isSpeakerOn = args["isSpeakerOn"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "isSpeakerOn is required", details: nil))
            return
        }
        
        // Check if ringback is playing before route change
        let wasRingbackPlaying = isRingbackPlaying
        
        guard let activeCall = activeCall else {
            // Call not created yet, store pending state and apply to iOS audio session
            pendingSpeakerState = isSpeakerOn
            self.isSpeakerOn = isSpeakerOn
            isHandlingAudioRouteChange = true
            toggleAudioRoute(toSpeaker: isSpeakerOn)
            logger.info(" Speaker state saved (pending): \(isSpeakerOn ? "enabled" : "disabled") (will apply when call connects)")
            sendEvent(isSpeakerOn ? "speakerOn" : "speakerOff")
            
            // If ringback was playing, restart it after route change
            if wasRingbackPlaying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    self.logger.info(" Restarting ringback after speaker toggle (call not created)")
                    self.startRingback()
                }
            }
            
            // Reset flag after a delay to allow route change to complete
            // Apple route changes sometimes take ~150-250ms, so 0.2s is safer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isHandlingAudioRouteChange = false
            }
            
            result(nil)
            return
        }
        
        // Check if call is connected
        let isCallConnected = activeCall.state == .connected
        
        if isCallConnected {
            // Call is connected, apply immediately
            isHandlingAudioRouteChange = true
            toggleAudioRoute(toSpeaker: isSpeakerOn)
            self.isSpeakerOn = isSpeakerOn
            logger.info(" Speaker \(isSpeakerOn ? "enabled" : "disabled")")
            sendEvent(isSpeakerOn ? "speakerOn" : "speakerOff")
            
            // Reset flag after a delay to allow route change to complete
            // Apple route changes sometimes take ~150-250ms, so 0.2s is safer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isHandlingAudioRouteChange = false
            }
        } else {
            // Call not connected yet - apply to iOS audio session immediately
            // and store pending state for when call connects
            isHandlingAudioRouteChange = true
            toggleAudioRoute(toSpeaker: isSpeakerOn)
            pendingSpeakerState = isSpeakerOn
            self.isSpeakerOn = isSpeakerOn
            logger.info(" Speaker \(isSpeakerOn ? "enabled" : "disabled") via iOS audio session (pending for Twilio when call connects)")
            sendEvent(isSpeakerOn ? "speakerOn" : "speakerOff")
            
            // If ringback was playing, restart it after route change
            if wasRingbackPlaying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self, self.activeCall != nil else { return }
                    // Only restart if call is still ringing (not connected yet)
                    if self.activeCall?.state != .connected {
                        self.logger.info(" Restarting ringback after speaker toggle (call not connected)")
                        self.startRingback()
                    }
                }
            }
            
            // Reset flag after a delay to allow route change to complete
            // Apple route changes sometimes take ~150-250ms, so 0.2s is safer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isHandlingAudioRouteChange = false
            }
        }
        
        result(nil)
    }
    
    private func handleSendDigits(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let digits = args["digits"] as? String,
              !digits.isEmpty else {
            logger.error(" Invalid digits argument")
            result(FlutterError(code: "INVALID_DIGITS", message: "Digits string is required", details: nil))
            return
        }
        
        guard let activeCall = activeCall else {
            // No active call - silently ignore
            result(nil)
            return
        }
        
        // Only send digits if call is connected, otherwise silently ignore
        guard activeCall.state == .connected else {
            result(nil)
            return
        }
        
        activeCall.sendDigits(digits)
        logger.info(" Digit sent: \(digits)")
        result(nil)
    }
    
    private func handleGetSid(_ result: @escaping FlutterResult) {
        let sid = activeCall?.sid
        logger.info(" Call SID: \(sid ?? "nil")")
        result(sid)
    }
    
    private func performVoiceCall(uuid: UUID, completionHandler: @escaping (Bool) -> Void) {
        guard let token = objc_getAssociatedObject(self, &AssociatedKeys.accessToken) as? String,
              !token.isEmpty else {
            logger.error(" Access token not found")
            completionHandler(false)
            return
        }
        
        guard let callOptions = objc_getAssociatedObject(self, &AssociatedKeys.callOptions) as? [String: String] else {
            logger.error(" Call options not found")
            completionHandler(false)
            return
        }
        
        let connectOptions = ConnectOptions(accessToken: token) { builder in
            for (key, value) in callOptions {
                builder.params[key] = value
            }
            builder.uuid = uuid
        }
        
        let call = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)
        activeCall = call
        callKitCompletionCallback = completionHandler
    }
    
    private func toggleAudioRoute(toSpeaker: Bool) {
        audioDevice.block = {
            DefaultAudioDevice.DefaultAVAudioSessionConfigurationBlock()
            do {
                if toSpeaker {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                } else {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                }
            } catch {
                self.logger.error("Error toggling audio route: \(error.localizedDescription)")
            }
        }
        audioDevice.block()
    }
    
    private func sendEvent(_ eventName: String) {
        guard let eventSink = eventSink else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            eventSink(eventName)
            self?.logger.info(" Event sent: \(eventName)")
        }
    }
    
    /**
     * Starts GSM ringback tone generation.
     *
     * GSM ringback tone specification:
     * - Frequency: 425 Hz sine wave
     * - Pattern: 1 second tone ON, 3 seconds tone OFF, repeating
     * - Uses AVAudioEngine for audio synthesis (no files required)
     *
     * Why AVAudioEngine?
     * - Native iOS audio framework for real-time audio processing
     * - Works correctly with VoIP audio sessions
     * - Properly integrates with CallKit and audio routing
     * - No file dependencies - pure audio synthesis
     */
    private func startRingback() {
        // Stop any existing ringback first
        stopRingback()
        
        guard !isRingbackPlaying else {
            logger.warning(" Ringback already playing, skipping")
            return
        }
        
        do {
            // Activate audio session (Twilio SDK should have already configured it)
            // We just need to ensure it's active for playback
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true, options: [])
            
            // GSM ringback tone parameters
            let sampleRate: Double = 44100.0
            let frequency: Double = 425.0 // Hz - GSM ringback tone frequency
            let toneDuration: Double = 1.0 // 1 second ON
            let pauseDuration: Double = 3.0 // 3 seconds OFF
            
            // Create audio engine
            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            
            // Attach player node to engine
            engine.attach(playerNode)
            
            // Create audio format (mono, 16-bit PCM)
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                     sampleRate: sampleRate,
                                     channels: 1,
                                     interleaved: false)!
            
            // Connect player node to main mixer
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            
            // Generate tone buffer (1 second of 425 Hz sine wave)
            let toneFrameCount = AVAudioFrameCount(sampleRate * toneDuration)
            let toneBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toneFrameCount)!
            toneBuffer.frameLength = toneFrameCount
            
            // Generate sine wave samples
            guard let channelData = toneBuffer.int16ChannelData else {
                logger.error(" Failed to get channel data for tone buffer")
                return
            }
            
            let channelDataPointer = channelData.pointee
            for frame in 0..<Int(toneFrameCount) {
                let angle = 2.0 * Double.pi * Double(frame) * frequency / sampleRate
                let sample = Int16(sin(angle) * Double(Int16.max))
                channelDataPointer[frame] = sample
            }
            
            // Generate silence buffer (3 seconds)
            let pauseFrameCount = AVAudioFrameCount(sampleRate * pauseDuration)
            let pauseBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: pauseFrameCount)!
            pauseBuffer.frameLength = pauseFrameCount
            
            // Fill silence buffer with zeros
            guard let pauseChannelData = pauseBuffer.int16ChannelData else {
                logger.error(" Failed to get channel data for pause buffer")
                return
            }
            
            let pauseChannelDataPointer = pauseChannelData.pointee
            memset(pauseChannelDataPointer, 0, Int(pauseFrameCount) * MemoryLayout<Int16>.size)
            
            // Start engine
            try engine.start()
            playerNode.play()
            
            // Store references
            ringbackEngine = engine
            ringbackPlayerNode = playerNode
            isRingbackPlaying = true
            
            logger.info(" GSM ringback tone started (425 Hz, 1s ON / 3s OFF)")
            
            // Schedule buffers in a loop
            scheduleRingbackLoop(toneBuffer: toneBuffer, pauseBuffer: pauseBuffer)
            
        } catch {
            logger.error(" Error starting ringback: \(error.localizedDescription)")
            stopRingback()
        }
    }
    
    /**
     * Schedules tone and pause buffers in a loop.
     * This method recursively schedules buffers to create the repeating pattern.
     */
    private func scheduleRingbackLoop(toneBuffer: AVAudioPCMBuffer, pauseBuffer: AVAudioPCMBuffer) {
        guard isRingbackPlaying, let playerNode = ringbackPlayerNode else {
            return
        }
        
        // Schedule tone (1 second)
        playerNode.scheduleBuffer(toneBuffer) { [weak self] in
            guard let self = self, self.isRingbackPlaying else { return }
            
            // Schedule pause (3 seconds)
            self.ringbackPlayerNode?.scheduleBuffer(pauseBuffer) { [weak self] in
                guard let self = self, self.isRingbackPlaying else { return }
                
                // Schedule next cycle
                DispatchQueue.main.async {
                    self.scheduleRingbackLoop(toneBuffer: toneBuffer, pauseBuffer: pauseBuffer)
                }
            }
        }
    }
    
    /**
     * Stops GSM ringback tone generation and releases all resources.
     *
     * This method:
     * - Stops the player node
     * - Stops and releases the audio engine
     * - Resets audio session if needed
     * - Ensures no resource leaks
     */
    private func stopRingback() {
        guard isRingbackPlaying || ringbackEngine != nil || ringbackPlayerNode != nil else {
            return
        }
        
        isRingbackPlaying = false
        
        // Stop player node
        ringbackPlayerNode?.stop()
        ringbackPlayerNode = nil
        
        // Stop and reset engine
        ringbackEngine?.stop()
        ringbackEngine?.reset()
        ringbackEngine = nil
        
        logger.info(" GSM ringback tone stopped")
    }
    
    /**
     * Plays busy tone (3 short beeps) when call is ended by user.
     *
     * Busy tone specification:
     * - Frequency: 425 Hz (same as ringback for consistency)
     * - Pattern: 3 short beeps (0.2s each) with 0.1s pauses between them
     * - Total duration: ~0.8 seconds
     * - Uses AVAudioEngine for audio synthesis (no files required)
     *
     * This is the standard "call ended" tone used in phone systems.
     */
    private func playBusyTone() {
        // Stop any existing busy tone first
        stopBusyTone()
        
        guard !isBusyTonePlaying else {
            logger.warning(" Busy tone already playing, skipping")
            return
        }
        
        do {
            // Activate audio session (Twilio SDK should have already configured it)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true, options: [])
            
            // Busy tone parameters
            let sampleRate: Double = 44100.0
            let frequency: Double = 425.0 // Hz - same as ringback
            let beepDuration: Double = 0.2 // 0.2 seconds per beep
            let pauseDuration: Double = 0.1 // 0.1 seconds pause between beeps
            let beepCount = 3 // 3 beeps total
            
            // Create audio engine
            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            
            // Attach player node to engine
            engine.attach(playerNode)
            
            // Create audio format (mono, 16-bit PCM)
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                     sampleRate: sampleRate,
                                     channels: 1,
                                     interleaved: false)!
            
            // Connect player node to main mixer
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            
            // Generate beep buffer (0.2 seconds of 425 Hz sine wave)
            let beepFrameCount = AVAudioFrameCount(sampleRate * beepDuration)
            let beepBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: beepFrameCount)!
            beepBuffer.frameLength = beepFrameCount
            
            // Generate sine wave samples for beep
            guard let channelData = beepBuffer.int16ChannelData else {
                logger.error(" Failed to get channel data for beep buffer")
                return
            }
            
            let channelDataPointer = channelData.pointee
            for frame in 0..<Int(beepFrameCount) {
                let angle = 2.0 * Double.pi * Double(frame) * frequency / sampleRate
                let sample = Int16(sin(angle) * Double(Int16.max))
                channelDataPointer[frame] = sample
            }
            
            // Generate silence buffer (0.1 seconds)
            let pauseFrameCount = AVAudioFrameCount(sampleRate * pauseDuration)
            let pauseBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: pauseFrameCount)!
            pauseBuffer.frameLength = pauseFrameCount
            
            // Fill silence buffer with zeros
            guard let pauseChannelData = pauseBuffer.int16ChannelData else {
                logger.error(" Failed to get channel data for pause buffer")
                return
            }
            
            let pauseChannelDataPointer = pauseChannelData.pointee
            memset(pauseChannelDataPointer, 0, Int(pauseFrameCount) * MemoryLayout<Int16>.size)
            
            // Start engine
            try engine.start()
            playerNode.play()
            
            // Store references
            busyToneEngine = engine
            busyTonePlayerNode = playerNode
            isBusyTonePlaying = true
            
            logger.info(" Busy tone started (3 beeps: 425 Hz, 0.2s ON / 0.1s OFF)")
            
            // Schedule 3 beeps with pauses between them
            for i in 0..<beepCount {
                // Schedule beep
                playerNode.scheduleBuffer(beepBuffer)
                
                // Schedule pause (except after last beep)
                if i < beepCount - 1 {
                    playerNode.scheduleBuffer(pauseBuffer)
                }
            }
            
            // Schedule completion handler to stop after all beeps finish
            let totalDuration = beepDuration * Double(beepCount) + pauseDuration * Double(beepCount - 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
                self?.stopBusyTone()
            }
            
        } catch {
            logger.error(" Error starting busy tone: \(error.localizedDescription)")
            stopBusyTone()
        }
    }
    
    /**
     * Stops busy tone playback and releases all resources.
     */
    private func stopBusyTone() {
        guard isBusyTonePlaying || busyToneEngine != nil || busyTonePlayerNode != nil else {
            return
        }
        
        isBusyTonePlaying = false
        
        // Stop player node
        busyTonePlayerNode?.stop()
        busyTonePlayerNode = nil
        
        // Stop and reset engine
        busyToneEngine?.stop()
        busyToneEngine?.reset()
        busyToneEngine = nil
        
        logger.info(" Busy tone stopped")
    }
    
    public func cleanup() {
        stopRingback()
        stopBusyTone()
        activeCall?.disconnect()
        activeCall = nil
        callUUID = nil
        eventSink = nil
        objc_setAssociatedObject(self, &AssociatedKeys.accessToken, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &AssociatedKeys.callOptions, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        isMuted = false
        isSpeakerOn = false
        pendingMuteState = nil
        pendingSpeakerState = nil
        callKitCompletionCallback = nil
        isHandlingAudioRouteChange = false
        
        // Remove audio route change observer
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        logger.info(" Twilio Voice channel cleaned up")
    }
}

// MARK: - FlutterStreamHandler
extension TwilioVoiceChannelHandler: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        logger.info("Event channel listener attached")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        logger.info("Event channel listener cancelled")
        return nil
    }
}

// MARK: - CXProviderDelegate
extension TwilioVoiceChannelHandler: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        logger.info("providerDidReset")
        audioDevice.isEnabled = false
    }
    
    func providerDidBegin(_ provider: CXProvider) {
        logger.info("providerDidBegin")
    }
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        logger.info("provider:didActivateAudioSession")
        audioDevice.isEnabled = true
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        logger.info("provider:didDeactivateAudioSession")
        audioDevice.isEnabled = false
    }
    
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        logger.info("provider:timedOutPerformingAction")
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        logger.info("provider:performStartCallAction")
        
        // Create call update with DTMF support enabled
        let callUpdate = CXCallUpdate()
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = true
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false
        
        // Report the call with DTMF support
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        provider.reportCall(with: action.callUUID, updated: callUpdate)
        
        performVoiceCall(uuid: action.callUUID) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.logger.info(" provider:performVoiceCall() successful")
                provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
                
                // Update call again when connected to ensure DTMF is available
                let connectedUpdate = CXCallUpdate()
                connectedUpdate.supportsDTMF = true
                connectedUpdate.supportsHolding = true
                connectedUpdate.supportsGrouping = false
                connectedUpdate.supportsUngrouping = false
                connectedUpdate.hasVideo = false
                provider.reportCall(with: action.callUUID, updated: connectedUpdate)
            } else {
                self.logger.error(" provider:performVoiceCall() failed")
            }
        }
        
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        logger.info("provider:performEndCallAction")
        
        if let call = activeCall {
            call.disconnect()
        }
        
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        logger.info("provider:performSetMutedAction")
        
        if let call = activeCall {
            call.isMuted = action.isMuted
            isMuted = action.isMuted
            sendEvent(action.isMuted ? "mute" : "unmute")
        }
        
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        logger.info("provider:performPlayDTMFCallAction - digit: \(action.digits)")
        
        // Handle DTMF from CallKit (when user presses digits in native call UI)
        // This is called when user presses digits in the native iOS call interface
        if let call = activeCall {
            if call.state == .connected {
                // Send digit through Twilio SDK
                call.sendDigits(action.digits)
                logger.info(" DTMF digit sent via CallKit to Twilio: \(action.digits)")
            } else {
                logger.warning(" Cannot send DTMF via CallKit: call not connected (state: \(call.state.rawValue))")
            }
        } else {
            logger.warning(" Cannot send DTMF via CallKit: no active call")
        }
        
        action.fulfill()
    }
}

// MARK: - CallDelegate
extension TwilioVoiceChannelHandler: CallDelegate {
    func callDidStartRinging(call: Call) {
        logger.info(" Call ringing")
        sendEvent("ringing")
        startRingback()
    }
    
    func callDidConnect(call: Call) {
        logger.info(" Call connected")
        stopRingback()
        sendEvent("connected")
        
        if let completion = callKitCompletionCallback {
            completion(true)
            callKitCompletionCallback = nil
        }
        
        // Update call with DTMF support when connected
        if let uuid = callUUID, let provider = callKitProvider {
            let callUpdate = CXCallUpdate()
            callUpdate.supportsDTMF = true
            callUpdate.supportsHolding = true
            callUpdate.supportsGrouping = false
            callUpdate.supportsUngrouping = false
            callUpdate.hasVideo = false
            provider.reportCall(with: uuid, updated: callUpdate)
            logger.info(" Call updated with DTMF support")
        }
        
        // Apply pending mute state if it was set before connection
        if let muteState = pendingMuteState {
            do {
                call.isMuted = muteState
                isMuted = muteState
                logger.info(" Applied pending mute state: \(muteState ? "muted" : "unmuted")")
            } catch {
                logger.error(" Error applying pending mute state: \(error.localizedDescription)")
            }
            pendingMuteState = nil
        }
        
        // Apply pending speaker state if it was set before connection
        // Note: We already applied it to iOS audio session before connection,
        // but now that Twilio SDK is connected, we need to ensure it's synced
        if let speakerState = pendingSpeakerState {
            // Post to main thread with a short delay to ensure Twilio SDK has fully initialized audio
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                do {
                    // Re-apply speaker state now that Twilio SDK is connected
                    self.isHandlingAudioRouteChange = true
                    self.toggleAudioRoute(toSpeaker: speakerState)
                    self.isSpeakerOn = speakerState
                    self.logger.info(" Synced speaker state with Twilio SDK: \(speakerState ? "enabled" : "disabled")")
                    
                    // Reset flag after a delay to allow route change to complete
                    // Apple route changes sometimes take ~150-250ms, so 0.2s is safer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.isHandlingAudioRouteChange = false
                    }
                } catch {
                    self.logger.error(" Error syncing speaker state with Twilio SDK: \(error.localizedDescription)")
                }
            }
            pendingSpeakerState = nil
        } else {
            // Set default audio route to receiver (not speaker) if no pending state
            toggleAudioRoute(toSpeaker: false)
        }
    }
    
    func call(call: Call, isReconnectingWithError error: Error) {
        logger.info(" Call reconnecting: \(error.localizedDescription)")
    }
    
    func callDidReconnect(call: Call) {
        logger.info(" Call reconnected")
    }
    
    func callDidFailToConnect(call: Call, error: Error) {
        logger.error(" Call failed to connect: \(error.localizedDescription)")
        stopRingback()
        sendEvent("callEnded")
        
        if let completion = callKitCompletionCallback {
            completion(false)
            callKitCompletionCallback = nil
        }
        
        if let uuid = callUUID {
            callKitProvider?.reportCall(with: uuid, endedAt: Date(), reason: .failed)
        }
        
        activeCall = nil
        callUUID = nil
        pendingMuteState = nil
        pendingSpeakerState = nil
    }
    
    func callDidDisconnect(call: Call, error: Error?) {
        logger.info(" Call disconnected: \(error?.localizedDescription ?? "normal disconnect")")
        stopRingback()
        
        let errorMessage = error?.localizedDescription ?? ""
        let isDeclined = errorMessage.contains("Decline") || errorMessage.contains("603")
        
        if isDeclined {
            sendEvent("declined")
        } else {
            sendEvent("callEnded")
        }
        
        if let uuid = callUUID {
            callKitProvider?.reportCall(with: uuid, endedAt: Date(), reason: error != nil ? .failed : .remoteEnded)
        }
        
        activeCall = nil
        callUUID = nil
        isMuted = false
        isSpeakerOn = false
        pendingMuteState = nil
        pendingSpeakerState = nil
    }
}

// MARK: - Associated Objects
private struct AssociatedKeys {
    static var callOptions: UInt8 = 0
    static var accessToken: UInt8 = 1
}

