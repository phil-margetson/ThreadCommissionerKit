//
//  ThreadCommissioner.swift
//  ThreadCommissioner
//
//  Created by Phil Margetson on 27/10/2025.
//

import Foundation


@MainActor
public class ThreadCommissioner {
    
    private let browser = HubDiscovery()
    private let commissioner = CommissionerHandler()
    
    public init() {
        assertRequiredInfoPlistEntries()
    }
    
    ///Starts a NWBrowser search for a device advertising the meshcop-e service- must be started in third party app first
    /// - Parameter timeout: The time in seconds for which to continue scanning mDNS for advertising hub
    /// - Returns: A `ThreadHub` containing the discovered IP address and port
    ///   used to start the DTLS session, or `nil` if the timeout expires.
    /// - Throws: `TimeoutError` if no hub is found within the specified period.
    public func searchForHub(timeout: TimeInterval) async throws -> ThreadHub? {
        guard timeout > 0 else {
            return await browser.waitForAdvertisingThreadHub()
        }
        let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
        return try await withThrowingTaskGroup(of: ThreadHub?.self, returning: ThreadHub?.self) { group in
            group.addTask { await self.browser.waitForAdvertisingThreadHub() }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds) // timeout task
                return nil
            }

            defer { group.cancelAll() }

            while let result = try await group.next() {
                if let hub = result {
                    return hub     // found hub
                } else {
                    throw HubDiscoveryError.notFound // timeout triggered
                }
            }
            throw HubDiscoveryError.notFound
        }
    }
    
    ///Connect DTLS session to advertising Thread hub
    /// - Parameters:
    ///     - threadHub: Hub details that is advertising the ephemeral meshcop-e service.
    ///     - adminCode: 9 digit code obtained by third party app belonging to specified hub
    /// - Throws: DTLS client error.
    public func connectToHub(threadHub: ThreadHub, adminCode: String) async throws {
        let commissioner = self.commissioner
        try await Task.detached(priority: .userInitiated) {
            try await commissioner.connect(borderRouterIP: threadHub.IP, port: threadHub.port, adminCode: adminCode)
        }.value
    }
    
    ///Obtain full Thread dataset from hub after obtaining connection
    /// - Returns:Thread dataset (panID, xpan, channel, shared key)
    /// - Throws: DTLS client error.
    public func getThreadDataset() async -> ThreadDataset? {
        let commissioner = self.commissioner
        return try? await Task.detached(priority: .userInitiated) {
            try await commissioner.getActiveDataset()
        }.value
    }
    
    public func close() {
        commissioner.close()
    }
    
    func setDTLSLoggingLevel(_ level: DTLSLoggingLevel) {
        commissioner.updateLoggingLevel(level)
    }
    
    private func assertRequiredInfoPlistEntries() {
        #if DEBUG
        let bundle = Bundle.main

        if bundle.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") == nil {
            assertionFailure("""
            ThreadCommissioner needs NSLocalNetworkUsageDescription \
            added to host app’s Info.plist explaining why local network access is required.
            """)
        }

        let expectedService = "_meshcop-e._udp"
        if let services = bundle.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] {
            let hasService = services.contains { $0.caseInsensitiveCompare(expectedService) == .orderedSame ||
                                                $0.caseInsensitiveCompare(expectedService + ".") == .orderedSame }
            if !hasService {
                assertionFailure("""
                ThreadCommissioner expects NSBonjourServices to include "\(expectedService)" \
                This is required to discover mDNS broadcast of _meshcop-e service.
                """)
            }
        } else {
            assertionFailure("""
            ThreadCommissioner requires NSBonjourServices (array) in Info.plist \
            listing "\(expectedService)".
            """)
        }
        
        if bundle.object(forInfoDictionaryKey: "NSBonjourUsageDescription") == nil {
            assertionFailure("""
            ThreadCommissioner needs NSBonjourUsageDescription added to the host app’s Info.plist \
            explaining why Bonjour service discovery is required.
            """)
        }
        #endif
    }
}
