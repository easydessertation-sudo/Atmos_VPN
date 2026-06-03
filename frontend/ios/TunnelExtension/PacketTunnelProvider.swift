import NetworkExtension
import os.log
import WireGuardKit

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.vaavix.atmosvpn.tunnel", category: "VPN")
    private var adapter: WireGuardAdapter?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        os_log("Starting AtmosVPN tunnel...", log: log, type: .info)

        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = proto.providerConfiguration,
              let wgConfigStr = providerConfig["wgConfig"] as? String else {
            let error = makeError("Invalid VPN configuration — missing wgConfig")
            os_log("Config error: %{public}@", log: log, type: .error, error.localizedDescription)
            completionHandler(error)
            return
        }

        do {
            let tunnelConfig = try TunnelConfiguration(fromWgQuickConfig: wgConfigStr, called: "AtmosVPN")
            
            let wgAdapter = WireGuardAdapter(with: self, logHandler: { logLevel, message in
                os_log("%{public}@", log: OSLog(subsystem: "com.vaavix.atmosvpn.tunnel", category: "WireGuard"), type: .default, message)
            })
            self.adapter = wgAdapter
            
            wgAdapter.start(tunnelConfiguration: tunnelConfig) { [weak self] adapterError in
                if let adapterError = adapterError {
                    os_log("Failed to start WireGuard adapter: %{public}@", log: self?.log ?? .default, type: .error, adapterError.localizedDescription)
                    completionHandler(adapterError)
                } else {
                    os_log("WireGuard adapter started successfully", log: self?.log ?? .default, type: .info)
                    completionHandler(nil)
                }
            }
        } catch {
            os_log("Failed to parse WireGuard config: %{public}@", log: log, type: .error, error.localizedDescription)
            completionHandler(error)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        os_log("Stopping tunnel, reason: %d", log: log, type: .info, reason.rawValue)
        guard let adapter = adapter else {
            completionHandler()
            return
        }
        
        adapter.stop {
            completionHandler()
        }
    }

    private func makeError(_ message: String) -> NSError {
        return NSError(
            domain: "com.vaavix.atmosvpn.tunnel",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
