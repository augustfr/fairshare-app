import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private var apiKey: String?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let mapsApiKeyChannel = FlutterMethodChannel(name: "mapsApiKeyChannel", binaryMessenger: controller.binaryMessenger)
        mapsApiKeyChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard call.method == "setApiKey" else {
                result(FlutterMethodNotImplemented)
                return
            }

            self?.handleSetApiKey(call, result: result)
        }

        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func handleSetApiKey(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let arguments = call.arguments as? [String: Any],
           let apiKey = arguments["apiKey"] as? String {
            self.apiKey = apiKey
            GMSServices.provideAPIKey(apiKey)
            result(nil)
        } else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid or missing arguments", details: nil))
        }
    }
}
