//
//  Types.swift
//  ThreadCommissioner
//
//  Public types for Thread Commercial Commissioning
//

import Foundation

/// Discovered Thread Hub information
public struct ThreadHub: Sendable {
    /// IP address of the Thread Border Router running the meshcop-e service
    public let IP: String
    /// Commissioner port of mDNS service
    public let port: UInt16

    public init(IP: String, port: UInt16) {
        self.IP = IP
        self.port = port
    }
}

/// Thread Operational Dataset containing network credentials
public struct ThreadDataset: Sendable {
    public var activeTimestamp: (seconds: UInt64, ticks: UInt16)?
    public var channel: (page: UInt8, id: UInt16)?
    public var channelMask: (page: UInt8, masks: [UInt32])?
    public var xpanid: Data?
    public var meshLocalPrefix: Data?
    public var networkKey: Data?
    public var networkName: String?
    public var panid: UInt16?
    public var pskc: Data?
    public var securityPolicy: (rotationHours: UInt16, flags: UInt16)?

    public init() {}
}

/// TLV types for Thread Operational Dataset
enum TlvType: UInt8 {
    case channel          = 0x00
    case panid            = 0x01
    case xpanid           = 0x02
    case networkName      = 0x03
    case pskc             = 0x04
    case networkKey       = 0x05
    case meshLocalPrefix  = 0x07
    case activeTimestamp  = 0x0E
    case securityPolicy   = 0x0C
    case channelMask      = 0x35
}

// MARK: - Utility Extensions

extension Data {
    func toHexString() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
