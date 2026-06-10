//
//  PacketTunnelProvider.swift
//  AtmosVPNTunnel
//
//  Created by user298977 on 6/9/26.
//

import Foundation
import NetworkExtension
import WireGuardKit // You MUST link WireGuardKit in Xcode for this to compile!

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private lazy var adapter: WireGuardAdapter = {
        return WireGuardAdapter(with: self) { logLevel, message in
            NSLog("WireGuardKit log: %{public}@", message)
        }
    }()
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // 1. Get the VPN configuration passed from Flutter via AppDelegate
        guard let tunnelProviderProtocol = self.protocolConfiguration as? NETunnelProviderProtocol,
              let tunnelConfiguration = tunnelProviderProtocol.providerConfiguration else {
            NSLog("WireGuardKit error: Missing provider configuration")
            completionHandler(NSError(domain: "AtmosVPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing provider configuration"]))
            return
        }
        
        // 2. Extract the raw WireGuard config string we passed in AppDelegate.swift
        guard let wgConfig = tunnelConfiguration["wgConfig"] as? String else {
            NSLog("WireGuardKit error: Missing wgConfig in provider configuration")
            completionHandler(NSError(domain: "AtmosVPN", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing wgConfig"]))
            return
        }
        
        // 3. Start the WireGuard Adapter
        adapter.start(tunnelConfiguration: wgConfig) { adapterError in
            if let adapterError = adapterError {
                NSLog("WireGuardKit error: Failed to start adapter: \(adapterError.localizedDescription)")
                completionHandler(adapterError)
                return
            }
            
            // Success! The tunnel is now actually routing traffic.
            NSLog("WireGuardKit successfully started tunnel!")
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { error in
            if let error = error {
                NSLog("WireGuardKit error: Failed to stop adapter: \(error.localizedDescription)")
            }
            completionHandler()
        }
    }
}
