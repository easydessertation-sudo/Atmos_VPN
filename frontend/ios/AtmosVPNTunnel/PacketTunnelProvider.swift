//
//  PacketTunnelProvider.swift
//  AtmosVPNTunnel
//
//  Created by user298977 on 6/9/26.
//

import Foundation
import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // VPN connection logic goes here
        completionHandler(nil)
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // VPN disconnection logic goes here
        completionHandler()
    }
}
