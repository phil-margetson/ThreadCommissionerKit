//
//  HubDiscovery.swift
//  ThreadCommissioner
//
//  mDNS/Bonjour discovery for Thread Border Routers
//

import Foundation
import Security
import Network

enum HubDiscoveryError: Error, LocalizedError {
    case notFound
    case addressResolution

    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Hub was not found during specified time period"
        case .addressResolution:
            return "IP address or port could not be resolved for broadcasting hub"
        }
    }
}

/// Main class for discovering Thread Border Routers via mDNS
@MainActor
final class HubDiscovery: NSObject, NetServiceDelegate {
    private var comissioningBrowser: NWBrowser?
    private var isBrowsing = false
    private var foundServices = [NetService]()
    private var ipStream: AsyncStream<String>!
    private var ipFoundContinuation: AsyncStream<String>.Continuation!
    
    // Stream for commissioner discovery (IP + port)
    private var commissionerStream: AsyncStream<(ThreadHub)>!
    private var commissionerContinuation: AsyncStream<(ThreadHub)>.Continuation!
    private(set) public var threadHub: ThreadHub?
    private var service: NetService!

    override init() {
        super.init()
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.ipStream = stream
        self.ipFoundContinuation = continuation
        let (commissionerStream, commissionerCont) = AsyncStream<(ThreadHub)>.makeStream()
        self.commissionerStream = commissionerStream
        self.commissionerContinuation = commissionerCont
        print("start commissioning browser")
        self.startCommissioningBrowser()
    }
    
    private func startCommissioningBrowser() {
        print("start commissioning browser")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let serviceType = "_meshcop-e._udp"
        self.comissioningBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        
        comissioningBrowser?.stateUpdateHandler = { newState in
            print("[HubDiscovery] Commissioner browser state updated: \(newState)")
        }
        
        comissioningBrowser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            Task {
                for result in results {
                    await self.resolveService(result)
                }
            }
        }
        self.comissioningBrowser?.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    func resolveService(_ result: NWBrowser.Result) {
        print("🔍 resolveService called for endpoint:", result.endpoint)
        guard case let .service(name, type, domain, _) = result.endpoint else {
            print("⚠️ Not a service endpoint")
            return
        }
        print("   Creating NetService - name:", name, "type:", type, "domain:", domain)
        let service = NetService(domain: domain, type: type, name: name)
        service.delegate = self
        foundServices.append(service)
        print("   Starting resolution with timeout 0...")
        service.resolve(withTimeout: 0)
    }

    nonisolated func netServiceDidStop(_ sender: NetService) {
        print("[HubDiscovery] Net service did stop")
    }
    
    // NetService delegate methods
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        print("✅ netServiceDidResolveAddress called for:", sender.name, "type:", sender.type)
        if let resolvedIP = resolveIPv4(addresses: sender.addresses!) {
            let name = sender.name
            let port = UInt16(sender.port)
            Task { @MainActor in
                self.updateCommissionerInfo(threadHub: ThreadHub(IP: resolvedIP, port: port))
                print("resolved IP for \(name) at \(resolvedIP) with port \(port)")
            }
        } else {
            print("could not resolve IP for \(sender.name)")
        }
    }
    
    private func updateCommissionerInfo(threadHub: ThreadHub) {
        print("stored thread hub")
        self.threadHub = threadHub
        commissionerContinuation.yield(threadHub)
    }
    
    func waitForAdvertisingThreadHub() async -> ThreadHub? {
        // If already discovered, return immediately
        if let existingThreadHub = self.threadHub {
            return existingThreadHub
        }
        for await value in commissionerStream {
            return value
        }
        return nil
    }
    
    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("❌ netService didNotResolve called for:", sender.name, "type:", sender.type, "error:", errorDict)
        print("[HubDiscovery] Failed to resolve service: \(sender), error: \(errorDict)")
        sender.resolve(withTimeout: 20)
    }

    nonisolated private func resolveIPv4(addresses: [Data]) -> String? {
        for addr in addresses {
            let data = addr as NSData
            var storage = sockaddr_storage()
            data.getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
            
            if Int32(storage.ss_family) == AF_INET {
                let addr4 = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        $0.pointee
                    }
                }
                let ip = String(cString: inet_ntoa(addr4.sin_addr), encoding: .ascii)
                return ip
            }
        }
        print("[HubDiscovery] No IPv4 address resolved")
        return nil
    }
}
