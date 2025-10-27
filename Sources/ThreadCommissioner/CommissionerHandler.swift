//
//  ThreadCommissioner.swift
//
//  Thread 1.4 commissioner using CoAP over DTLS

import Foundation

public enum CommissionerError: Error {
    case connectionFailed(String)
    case petitionFailed(String)
    case datasetRequestFailed(String)
    case invalidResponse(String)
}

// MARK: - CoAP Message Types

enum CoAPType: UInt8 {
    case confirmable = 0    // CON
    case nonConfirmable = 1 // NON
    case acknowledgement = 2 // ACK
    case reset = 3          // RST
}

enum CoAPCode: UInt8 {
    // Req codes
    case empty = 0         // 0.00 Empty message (ACK/RST)
    case get = 1
    case post = 2
    case put = 3
    case delete = 4

    // Response codes
    case created = 65      // 2.01
    case deleted = 66      // 2.02
    case valid = 67        // 2.03
    case changed = 68      // 2.04
    case content = 69      // 2.05
    case badRequest = 128  // 4.00
    case unauthorized = 129 // 4.01
    case notFound = 132    // 4.04
}

enum CoAPOptionNumber: UInt16 {
    case uriPath = 11
    case contentFormat = 12
    case uriQuery = 15
}

// MARK: - CoAP Message Builder

struct CoAPMessage {
    let type: CoAPType
    let code: CoAPCode
    let messageId: UInt16
    let token: Data
    let options: [(CoAPOptionNumber, Data)]
    let payload: Data?

    func encode() -> Data {
        var data = Data()

        // CoAP header (4 bytes)
        // Version (2 bits) = 1, Type (2 bits), Token Length (4 bits)
        let version: UInt8 = 1
        let tokenLength = UInt8(min(token.count, 8))
        let byte0 = (version << 6) | (type.rawValue << 4) | tokenLength
        data.append(byte0)

        // Code (1 byte)
        data.append(code.rawValue)

        // Message ID (2 bytes, big-endian)
        data.append(UInt8((messageId >> 8) & 0xFF))
        data.append(UInt8(messageId & 0xFF))

        // Token (0-8 bytes)
        data.append(token)

        // Options (sorted by option number)
        var previousOptionNumber: UInt16 = 0
        for (optionNumber, optionValue) in options.sorted(by: { $0.0.rawValue < $1.0.rawValue }) {
            let delta = Int(optionNumber.rawValue) - Int(previousOptionNumber)
            let length = optionValue.count

            // Option header
            var optionHeader: UInt8 = 0
            if delta < 13 {
                optionHeader |= UInt8(delta << 4)
            } else if delta < 269 {
                optionHeader |= 13 << 4
            }

            if length < 13 {
                optionHeader |= UInt8(length)
            } else if length < 269 {
                optionHeader |= 13
            }

            data.append(optionHeader)

            // Extended option delta
            if delta >= 13 && delta < 269 {
                data.append(UInt8(delta - 13))
            }

            // Extended option length
            if length >= 13 && length < 269 {
                data.append(UInt8(length - 13))
            }

            // Option value
            data.append(optionValue)
            previousOptionNumber = optionNumber.rawValue
        }

        // Payload (if present)
        if let payload = payload, !payload.isEmpty {
            data.append(0xFF) // Payload marker
            data.append(payload)
        }

        return data
    }

    static func decode(_ data: Data) -> CoAPMessage? {
        guard data.count >= 4 else { return nil }
        var offset = 0

        // Parse header
        let byte0 = data[offset]
        let version = (byte0 >> 6) & 0x03
        guard version == 1 else { return nil }

        let typeRaw = (byte0 >> 4) & 0x03
        guard let type = CoAPType(rawValue: typeRaw) else { return nil }

        let tokenLength = Int(byte0 & 0x0F)
        offset += 1

        let codeRaw = data[offset]
        guard let code = CoAPCode(rawValue: codeRaw) else { return nil }
        offset += 1

        let messageId = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        offset += 2

        // Parse token
        guard data.count >= offset + tokenLength else { return nil }
        let token = data.subdata(in: offset..<offset + tokenLength)
        offset += tokenLength

        // Parse options and payload
        var options: [(CoAPOptionNumber, Data)] = []
        var payload: Data?
        var currentOptionNumber: UInt16 = 0

        while offset < data.count {
            let byte = data[offset]

            // Check for payload marker
            if byte == 0xFF {
                offset += 1
                if offset < data.count {
                    payload = data.subdata(in: offset..<data.count)
                }
                break
            }

            // Parse option
            var delta = Int((byte >> 4) & 0x0F)
            var length = Int(byte & 0x0F)
            offset += 1

            // Extended delta
            if delta == 13 {
                guard offset < data.count else { break }
                delta = Int(data[offset]) + 13
                offset += 1
            }

            // Extended length
            if length == 13 {
                guard offset < data.count else { break }
                length = Int(data[offset]) + 13
                offset += 1
            }

            currentOptionNumber += UInt16(delta)

            guard offset + length <= data.count else { break }
            let optionValue = data.subdata(in: offset..<offset + length)
            offset += length

            if let optionNum = CoAPOptionNumber(rawValue: currentOptionNumber) {
                options.append((optionNum, optionValue))
            }
        }

        return CoAPMessage(type: type, code: code, messageId: messageId, token: token, options: options, payload: payload)
    }
}

// MARK: - Thread Commissioner Client

nonisolated(unsafe) class CommissionerHandler {
    private let dtlsClient: ThreadDTLSClient
    private var messageId: UInt16 = 0
    private let sessionId: Data

    init() {
        self.dtlsClient = ThreadDTLSClient()
        // Generate random session ID
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        self.sessionId = Data(bytes)
    }

    /// Connect to Thread Border Router commissioner endpoint
    /// - Parameters:
    ///   - borderRouterIP: IP address of the Thread Border Router
    ///   - port: Commissioner port (typically 49191, but can vary)
    ///   - adminCode: Admin code for EC-JPAKE authentication
    nonisolated(nonsending) func connect(borderRouterIP: String, port: UInt16, adminCode: String) async throws {
        print("🔗 Connecting to Border Router at \(borderRouterIP):\(port)")

        try await dtlsClient.connect(host: borderRouterIP, port: port, adminCode: adminCode)

        print("✅ Connected to Border Router")
    }

    /// Send Commissioner Petition to become active commissioner
    nonisolated(nonsending) private func petition() async throws {
        let commissionerName = "iOSCommissioner"
        print("📝 Sending Commissioner Petition...")

        // Build CoAP POST to /c/cp (Commissioner Petition)
        let token = Data([0x01, 0x02, 0x03, 0x04])
        messageId += 1

        // URI-Path: "c" and "cp"
        let pathOptions: [(CoAPOptionNumber, Data)] = [
            (.uriPath, "c".data(using: .utf8)!),
            (.uriPath, "cp".data(using: .utf8)!)
        ]

        // Payload: Commissioner ID TLV (type=1, length, value)
        var payload = Data()
        let commissionerIdData = commissionerName.data(using: .utf8)!
        payload.append(1) // Type: Commissioner ID
        payload.append(UInt8(commissionerIdData.count)) // Length
        payload.append(commissionerIdData) // Value

        let message = CoAPMessage(
            type: .confirmable,
            code: .post,
            messageId: messageId,
            token: token,
            options: pathOptions,
            payload: payload
        )

        let request = message.encode()
        print("📤 Sending petition: \(request.count) bytes")
        try dtlsClient.send(request)

        // Wait for response (may get Empty ACK first, then actual response)
        var response = try dtlsClient.receive()
        guard var coapResponse = CoAPMessage.decode(response) else {
            throw CommissionerError.petitionFailed("Invalid CoAP response")
        }

        print("📥 Petition response code: \(coapResponse.code.rawValue) (type: \(coapResponse.type))")

        // If we got an Empty ACK, wait for the actual response
        if coapResponse.code == .empty && coapResponse.type == .acknowledgement {
            print("⏳ Received Empty ACK, waiting for actual response...")
            response = try dtlsClient.receive()
            guard let actualResponse = CoAPMessage.decode(response) else {
                throw CommissionerError.petitionFailed("Invalid CoAP response after Empty ACK")
            }
            coapResponse = actualResponse
            print("📥 Actual response code: \(coapResponse.code.rawValue)")
        }

        if coapResponse.code == .changed {
            print("✅ Petition accepted - now active commissioner")
        } else {
            throw CommissionerError.petitionFailed("Petition rejected with code \(coapResponse.code.rawValue)")
        }
    }

    /// Get Active Operational Dataset (contains network credentials)
    nonisolated(nonsending) func getActiveDataset() async throws -> ThreadDataset {
        try await petition() //make active commissioner first
        print("📊 Requesting Active Operational Dataset...")
        print("🔍 Trying endpoint: /c/ag (Active Dataset GET)...")
        let dataset = try await requestDataset(endpoint: "ag")
        return dataset
    }

    nonisolated(nonsending) private func requestDataset(endpoint: String) async throws -> ThreadDataset {
        let token = Data([0x05, 0x06, 0x07, 0x08])
        messageId += 1

        let pathOptions: [(CoAPOptionNumber, Data)] = [
            (.uriPath, "c".data(using: .utf8)!),
            (.uriPath, endpoint.data(using: .utf8)!)
        ]

        // For MGMT_ACTIVE_GET, we might need to send TLVs requesting specific data
        var payload: Data? = nil
        if endpoint == "ag" {
            // Request corresponding dataset components
            // TLV format: Type(1) + Length(1) + Value(N)
            var getTlvs = Data()
            getTlvs.append(13) // Type: Get TLV (0x0D)
            getTlvs.append(6)  // Length: 6 TLV types to request
            getTlvs.append(0)  // Channel
            getTlvs.append(1)  // PAN ID
            getTlvs.append(2)  // Extended PAN ID
            getTlvs.append(3)  // Network Name
            getTlvs.append(5)  // Network Key
            getTlvs.append(14) // Active Timestamp
            payload = getTlvs
        }

        let message = CoAPMessage(
            type: .confirmable,
            code: .post,  // Use POST for MGMT commands
            messageId: messageId,
            token: token,
            options: pathOptions,
            payload: payload
        )
        print(pathOptions)
        let request = message.encode()
        print("📤 Sending dataset request to /c\(endpoint): \(request.count) bytes")
        if let p = payload {
            print("Payload: \(p.toHexString())")
        }
        try dtlsClient.send(request)

        // Wait for response (may get Empty ACK)
        var response = try dtlsClient.receive()
        guard var coapResponse = CoAPMessage.decode(response) else {
            throw CommissionerError.datasetRequestFailed("Invalid CoAP response")
        }

        print("📥 Dataset response code: \(coapResponse.code.rawValue) (type: \(coapResponse.type))")

        // If we got an Empty ACK, wait for the actual response
        if coapResponse.code == .empty && coapResponse.type == .acknowledgement {
            print("⏳ Received Empty ACK, waiting for actual response...")
            response = try dtlsClient.receive()
            guard let actualResponse = CoAPMessage.decode(response) else {
                throw CommissionerError.datasetRequestFailed("Invalid CoAP response after Empty ACK")
            }
            coapResponse = actualResponse
            print("📥 Actual response code: \(coapResponse.code.rawValue)")
        }

        guard coapResponse.code == .changed || coapResponse.code == .content,
              let payload = coapResponse.payload else {
            throw CommissionerError.datasetRequestFailed("No dataset in response (code: \(coapResponse.code.rawValue))")
        }

        print("📦 Received dataset: \(payload.count) bytes")
        print("   Raw: \(payload.toHexString())")

        // Parse TLV-encoded dataset
        return parseDataset(from: payload)
    }

    /// Parse Thread Operational Dataset TLVs
    private func parseDataset(from bytes: Data) -> ThreadDataset {
        var ds = ThreadDataset()
        var i = 0
        let b = [UInt8](bytes)
        while i + 2 <= b.count {
            let t = b[i]; let len = Int(b[i+1]); i += 2
            guard i + len <= b.count, let tt = TlvType(rawValue: t) else { i += len; continue }
            let v = Array(b[i ..< i+len]); i += len

            switch tt {
            case .activeTimestamp:
                // 8 bytes: 48-bit seconds (big-endian) + 16-bit ticks
                guard v.count == 8 else { break }
                let seconds = UInt64(v[0])<<40 | UInt64(v[1])<<32 | UInt64(v[2])<<24 |
                              UInt64(v[3])<<16 | UInt64(v[4])<<8  | UInt64(v[5])
                let ticks   = UInt16(v[6])<<8 | UInt16(v[7])
                ds.activeTimestamp = (seconds, ticks)

            case .channel:
                // 3 bytes: page(1), channel(2) big-endian
                guard v.count == 3 else { break }
                ds.channel = (v[0], UInt16(v[1])<<8 | UInt16(v[2]))

            case .channelMask:
                // page(1), maskLen(1), then N*4-byte masks (big-endian)
                guard v.count >= 2, (v.count - 2) % 4 == 0 else { break }
                let page = v[0], maskLen = Int(v[1])
                var masks: [UInt32] = []
                for off in stride(from: 2, to: 2+maskLen, by: 4) {
                    let m = UInt32(v[off])<<24 | UInt32(v[off+1])<<16 |
                            UInt32(v[off+2])<<8  | UInt32(v[off+3])
                    masks.append(m)
                }
                ds.channelMask = (page, masks)

            case .xpanid:
                guard v.count == 8 else { break }
                ds.xpanid = Data(v)

            case .meshLocalPrefix:
                // 8 bytes = /64 prefix
                guard v.count == 8 else { break }
                ds.meshLocalPrefix = Data(v)

            case .networkKey:
                guard v.count == 16 else { break }
                ds.networkKey = Data(v)

            case .networkName:
                ds.networkName = String(bytes: v, encoding: .utf8)

            case .panid:
                guard v.count == 2 else { break }
                ds.panid = UInt16(v[0])<<8 | UInt16(v[1])

            case .pskc:
                guard v.count == 16 else { break }
                ds.pskc = Data(v)

            case .securityPolicy:
                // rotationHours(2) + flags(2) big-endian
                guard v.count >= 4 else { break }
                let rotation = UInt16(v[0])<<8 | UInt16(v[1])
                let flags    = UInt16(v[2])<<8 | UInt16(v[3])
                ds.securityPolicy = (rotation, flags)
            }
        }
        print(ds)
        return ds
    }

    public func close() {
        dtlsClient.close()
    }
    
    nonisolated func updateLoggingLevel(_ level: DTLSLoggingLevel) {
        dtlsClient.updateLoggingLevel(level)
    }
}

extension CommissionerHandler: @unchecked Sendable {}

// swiftlint:enable all
