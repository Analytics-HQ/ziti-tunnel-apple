//
//  PacketTunnelProvider.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 3/30/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import NetworkExtension

enum ZitiPacketTunnelError : Error {
    case configurationError
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    var conf = [String: AnyObject]()
    var selfDNS = ""
    
    private func processDNS(_ dns:DNSPacket) {
        NSLog("DNS-->: \(dns.debugDescription)")
        
        let dnsR = DNSPacket(dns, questions:dns.questions)
        NSLog("<--DNS: \(dnsR.debugDescription)")
        NSLog("<--UDP: \(dnsR.udp.debugDescription)")
        NSLog("<--IP: \(dnsR.udp.ip.debugDescription)")
    }
    
    private func processUDP(_ udp:UDPPacket) {
        NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if udp.ip.destinationAddressString == self.selfDNS && udp.destinationPort == 53 {
            if let dns = DNSPacket(udp) {
                processDNS(dns)
            }
        }
    }
    
    /*
     private func processTCP(_ tcp:TCPPacket) {
     
     }*/
    
    private func processIP(_ ip:IPv4Packet) {
        NSLog("IP-->: \(ip.debugDescription)")
        if (ip.protocolId == IPv4ProtocolId.UDP) {
            if let udp = UDPPacket(ip) {
                processUDP(udp)
            }
        }
    }
    
    func readPacketFlow() {
        self.packetFlow.readPacketObjects { (packets:[NEPacket]) in
            NSLog("Got \(packets.count) packets!")
            for packet:NEPacket in packets {
                if let ip = IPv4Packet(data:packet.data) {
                    self.processIP(ip)
                }
            }
            self.readPacketFlow()
        }
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        NSLog("startTunnel")
        
        conf = (self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration! as [String : AnyObject]
        
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: self.protocolConfiguration.serverAddress!)
        
        if let ip = conf["ip"], let subnet = conf["subnet"], let mtu = conf["mtu"], let dns = conf["dns"] {
            
            tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [ip as! String],
                                                                subnetMasks: [subnet as! String])
            
            let includedRoute = NEIPv4Route(destinationAddress: ip as! String,
                                            subnetMask: subnet as! String)
            
            tunnelNetworkSettings.ipv4Settings?.includedRoutes = [includedRoute]
            tunnelNetworkSettings.mtu = Int(mtu as! String) as NSNumber?
            
            self.selfDNS = (dns as! String).components(separatedBy: ",")[0]
            let dnsSettings = NEDNSSettings(servers: (dns as! String).components(separatedBy: ","))
            if let matchDomains = conf["matchDomains"] {
                dnsSettings.matchDomains = (matchDomains as! String).components(separatedBy: ",")
            } else {
                dnsSettings.matchDomains = [""]
            }
            tunnelNetworkSettings.dnsSettings = dnsSettings
            
        } else {
            NSLog("Invalid configuration")
            completionHandler(ZitiPacketTunnelError.configurationError)
            return
        }
        
        NSLog("dnsSettings.matchDomains = \(String(describing: tunnelNetworkSettings.dnsSettings?.matchDomains))")
        NSLog("selfDNS = \(self.selfDNS)")

        self.setTunnelNetworkSettings(tunnelNetworkSettings) { (error: Error?) -> Void in
            if let error = error {
                NSLog(error.localizedDescription)
                // TODO: status and get outta here
            }
            
            // if all good, start listening for for ziti protocol..
        }
        
        // call completion handler with nil to indicate success (TODO: better approach would be make sure we
        // get a bit further along...)
        completionHandler(nil)
        
        //
        // Start listening for traffic headed our way via the tun interface
        //
        readPacketFlow();
        
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("stopTunnel")

        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let messageString = NSString(data: messageData, encoding: String.Encoding.utf8.rawValue) else {
            completionHandler?(nil)
            return
        }
        NSLog("PTP Got message from app... \(messageString)")
        
        if let handler = completionHandler {
            handler(messageData)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
}
