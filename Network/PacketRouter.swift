//
//  PacketRouter.swift
//  PacketTunnelProvider
//
//  Created by David Hart on 4/24/18.
//  Copyright © 2018 David Hart. All rights reserved.
//

import NetworkExtension
import Foundation

class PacketRouter : NSObject {
    let tunnelProvider:PacketTunnelProvider
    let dnsResolver:DNSResolver
    var tcpSessions:[String:TCPSession] = [:]

    init(tunnelProvider:PacketTunnelProvider, dnsResolver:DNSResolver) {
        self.tunnelProvider = tunnelProvider
        self.dnsResolver = dnsResolver
    }
    
    private func routeUDP(_ udp:UDPPacket) {
        //NSLog("UDP-->: \(udp.debugDescription)")
        
        // if this is a DNS request sent to us, handle it
        if self.dnsResolver.needsResolution(udp) {
            dnsResolver.resolve(udp)
        } else {
            // TODO: --> Ziti
            NSLog("...UDP --> meant for Ziti? UDP not yet supported")
        }
    }
    
    private func routeTCP(_ pkt:TCPPacket) {
        //NSLog("Router routing curr thread = \(Thread.current)")
        NSLog("TCP-->: \(pkt.debugDescription)")
        
        let intercept = "\(pkt.ip.destinationAddressString):\(pkt.destinationPort)"
        let (zidR, svcR) = tunnelProvider.getServiceForIntercept(intercept)
        guard let zid = zidR, let svc = svcR, let svcName = svc.name else {
            // TODO: find better approach for matched IP but not port
            //    Possibility (for DNS based): store the original IP before intercepting DNS, proxy to it
            //    For non-DNS - hmmm. Raw sockets? need additional privs.. some way to force packet to en0 ala iptables
            //       if iptables like filters can be setup programatically/relyably this would work for DNS or IP...
            NSLog("Router: no service found for \(intercept). Dropping packet")
            return
        }
        
        var tcpSession:TCPSession
        let key = "TCP:\(pkt.ip.sourceAddressString):\(pkt.sourcePort)->\(zid.name):\(svcName)"
        NSLog("Router, \(key) identity:\(zid.id)\n service identity:\(svc.id ?? "unknown")")
        if let foundSession = tcpSessions[key] {
            tcpSession = foundSession
        } else {
            let mtu = tunnelProvider.providerConfig.mtu
            tcpSession = TCPSession(key, zid, svc, mtu) { [weak self] respPkt in
                guard let respPkt = respPkt else {
                    // remove connection
                    NSLog("Router nil packet write, removing con: \(key)")
                    self?.tcpSessions.removeValue(forKey: key)
                    return
                }
                NSLog("<--TCP: \(respPkt.debugDescription)")
                self?.tunnelProvider.writePacket(respPkt.ip.data)
            }
            tcpSessions[key] = tcpSession
        }
        
        let state = tcpSession.tcpReceive(pkt)
        if state == TCPSession.State.TIME_WAIT || state == TCPSession.State.Closed {
            NSLog("Router removing con on state \(state): \(key)")
            tcpSessions.removeValue(forKey: key)
        }
    }

    private func createIPPacket(_ data:Data) -> IPPacket? {
        let ip:IPPacket
        
        guard data.count > 0 else {
            NSLog("Invalid (empty) data for IPPacket")
            return nil
        }
        
        let version = data[0] >> 4
        switch version {
        case 4:
            guard let v4Packet = IPv4Packet(data) else {
                NSLog("Unable to create IPv4Packet from data")
                return nil
            }
            ip = v4Packet
        case 6:
            guard let v6Packet = IPv6Packet(data) else {
                NSLog("Unable to create IPv6Packet from data")
                return nil
            }
            ip = v6Packet
        default:
            NSLog("Unable to create IPPacket from data. Unrecocognized IP version")
            return nil
        }
        return ip
    }
    
    func route(_ data:Data) {
        guard let ip = self.createIPPacket(data) else {
            NSLog("Unable to create IPPacket for routing")
            return
        }
        
        //NSLog("IP-->: \(ip.debugDescription)")
        switch ip.protocolId {
        case IPProtocolId.UDP:
            if let udp = UDPPacket(ip) {
                routeUDP(udp)
            }
        case IPProtocolId.TCP:
            if let tcp = TCPPacket(ip) {
                routeTCP(tcp)
            }
        default:
            NSLog("No support for protocol \(ip.protocolId)")
        }
    }
}
