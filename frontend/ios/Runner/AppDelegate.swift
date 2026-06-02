import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Get the Flutter view controller
        let controller: FlutterViewController
        if let windowVC = window?.rootViewController as? FlutterViewController {
            controller = windowVC
        } else {
            // Fallback for newer Flutter versions using SceneDelegate
            controller = FlutterViewController(engine: FlutterEngine(name: "io.flutter"), nibName: nil, bundle: nil)
        }

        // VPN MethodChannel — must match the Dart and Android channel name exactly
        let vpnChannel = FlutterMethodChannel(
            name: "com.atmosvpn/vpn",
            binaryMessenger: controller.binaryMessenger
        )

        vpnChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "connect":
                if let args = call.arguments as? [String: Any],
                   let config = args["config"] as? String {
                    let killSwitch = args["killSwitch"] as? Bool ?? false
                    self?.connectVpn(config: config, killSwitch: killSwitch, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "No WireGuard config provided", details: nil))
                }
            case "disconnect":
                self?.disconnectVpn(result: result)
            case "isConnected":
                self?.checkStatus(result: result)
            case "getError":
                result(nil) // Errors are reported via the connection status on iOS
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - VPN Control

    private func connectVpn(config: String, killSwitch: Bool, result: @escaping FlutterResult) {
        // Load existing managers or create a new one
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                result(FlutterError(code: "LOAD_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()
            self?.configureAndStart(manager: manager, config: config, killSwitch: killSwitch, result: result)
        }
    }

    private func configureAndStart(
        manager: NETunnelProviderManager,
        config: String,
        killSwitch: Bool,
        result: @escaping FlutterResult
    ) {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.vaavix.atmosvpn.tunnel"
        proto.serverAddress = "AtmosVPN"
        proto.providerConfiguration = ["wgConfig": config]

        // Disconnect rule: if the tunnel drops, block all traffic (Kill Switch)
        proto.disconnectOnSleep = !killSwitch

        manager.protocolConfiguration = proto
        manager.localizedDescription = "AtmosVPN"
        manager.isEnabled = true

        if killSwitch {
            // On-demand: keep VPN alive always (Kill Switch)
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any
            manager.onDemandRules = [connectRule]
            manager.isOnDemandEnabled = true
        } else {
            manager.onDemandRules = []
            manager.isOnDemandEnabled = false
        }

        manager.saveToPreferences { error in
            if let error = error {
                result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            // Must reload after saving before starting
            manager.loadFromPreferences { error in
                if let error = error {
                    result(FlutterError(code: "RELOAD_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                do {
                    try manager.connection.startVPNTunnel()
                    result(true)
                } catch {
                    result(FlutterError(code: "START_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func disconnectVpn(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let manager = managers?.first {
                manager.isOnDemandEnabled = false  // Disable on-demand so it stays OFF
                manager.saveToPreferences { _ in
                    manager.connection.stopVPNTunnel()
                    result(true)
                }
            } else {
                result(true) // No manager = nothing to stop
            }
        }
    }

    private func checkStatus(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            let isConnected = managers?.first?.connection.status == .connected
            result(isConnected)
        }
    }
}
