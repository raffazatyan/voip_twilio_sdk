import Flutter
import UIKit

@objc public class VoipTwilioSdkPlugin: NSObject, FlutterPlugin {
    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        TwilioVoiceChannelHandler.shared.setup(with: registrar.messenger())
    }
    
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        TwilioVoiceChannelHandler.shared.cleanup()
    }
}

