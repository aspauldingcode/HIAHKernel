import NetworkExtension
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // Configure IPv4 settings for loopback
        let ipv4Settings = NEIPv4Settings(addresses: ["127.0.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = []
        settings.ipv4Settings = ipv4Settings
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Start em-proxy
            // Note: In the actual extension, we call into the bridge to start the binary
            let result = EMProxyBridge.startVPN(withBindAddress: "127.0.0.1:65399")
            if result != 0 {
                completionHandler(NSError(domain: "PacketTunnelProvider", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Failed to start em-proxy"]))
                return
            }
            
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        EMProxyBridge.stopVPN()
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the main app
        if let message = String(data: messageData, encoding: .utf8) {
            print("[PacketTunnelProvider] Received message: \(message)")
        }
        completionHandler?(nil)
    }
}
