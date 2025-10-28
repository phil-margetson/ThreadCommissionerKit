# ThreadCommissionerKit

A Swift package for Thread 1.4 commissioning on iOS/macOS. Automatically retrieve Thread network credentials from Thread Border Routers using mDNS and EC-JPAKE authentication with ephemeral admin codes(ePSKc) over DTLS.

## Features

- ✅ **mDNS/Bonjour Discovery**: Automatic discovery of Thread Border Routers via `_meshcop-e._udp` service
- ✅ **EC-JPAKE Authentication**: Secure authentication using ephemeral admin codes (no pre-shared network credentials needed)
- ✅ **DTLS 1.2**: Secure communication over UDP using mbedTLS with `TLS-ECJPAKE-WITH-AES-128-CCM-8` ciphersuite
- ✅ **CoAP Protocol**: Constrained Application Protocol for commissioner operations
- ✅ **Thread Dataset Retrieval**: Automatic parsing of Thread Operational Dataset (network credentials)
- ✅ **Swift Async/Await Design**: Built natively for Swift's modern concurrency model, supporting structured concurrency and async workflows

## Requirements

- iOS 15.0+ / macOS 12.0+
- Xcode 14.0+
- Swift 5.9+

## Installation

### Swift Package Manager (Xcode Project)

Add the package to your Xcode project:

1. In Xcode, open **File → Add Package Dependencies**
2. Enter the repository URL for ThreadCommissionerKit
3. Select the latest version or main branch
4. Add the package to your app target (iOS or macOS)

**Note:** The package includes `mbedTLS.xcframework` internally, so you don't need to embed or import mbedTLS manually.

### Required Info.plist Keys

To use Bonjour/mDNS and local network access, you must include these keys in your app’s Info.plist:

```xml
<key>NSBonjourServices</key>
<array>
    <string>_meshcop-e._udp</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>Required to discover Thread Border Routers on your local network.</string>
<key>NSBonjourUsageDescription</key>
<string>Required to advertise and discover Thread services via Bonjour.</string>
```

## Usage

### Basic Example

```swift
import ThreadCommissionerKit

@MainActor
func discoverAndCommission(adminCode: String) async {
    let commissioner = ThreadCommissioner()

    guard let threadHub = await commissioner.searchForHub(timeout: 10) else {
        print("No Thread hub found. Make sure commissioning is enabled on the router.")
        return
    }

    do {
        try await commissioner.connectToHub(threadHub: threadHub, adminCode: adminCode)
        if let dataset = await commissioner.getThreadDataset() {
            print("Success! Thread dataset:", dataset)
        } else {
            print("Connected, but no dataset returned.")
        }
    } catch {
        print("Error communicating with Thread hub:", error.localizedDescription)
    }
    
    commissioner.close()
}
```

### Thread Network Credentials

The `Dataset` structure contains all Thread network credentials:

```swift
public struct Dataset {
    var activeTimestamp: (seconds: UInt64, ticks: UInt16)?
    var channel: (page: UInt8, id: UInt16)?
    var channelMask: (page: UInt8, masks: [UInt32])?
    var xpanid: Data?                    // Extended PAN ID (8 bytes)
    var meshLocalPrefix: Data?           // Mesh-Local Prefix (8 bytes)
    var networkKey: Data?                // Network Key (16 bytes)
    var networkName: String?             // Network Name
    var panid: UInt16?                   // PAN ID
    var pskc: Data?                      // PSKc (16 bytes)
    var securityPolicy: (rotationHours: UInt16, flags: UInt16)?
}
```

## How It Works

### Thread 1.4 Commercial Commissioning Flow

1. **Discovery**: Use mDNS to discover Thread Border Router advertising `_meshcop-e._udp` service
2. **DTLS Handshake**: Establish secure DTLS connection using EC-JPAKE with admin code
3. **Commissioner Petition**: Send CoAP petition to become active commissioner
4. **Dataset Request**: Request Active Operational Dataset via CoAP
5. **Parse Credentials**: Parse TLV-encoded Thread network credentials into a Swift struct

### Security

- **EC-JPAKE**: Password-Authenticated Key Exchange provides mutual authentication without transmitting the admin code
- **Ephemeral Codes**: Admin codes are temporary and can be revoked
- **DTLS Encryption**: All communication is encrypted using AES-128-CCM-8

## Supported Thread Border Routers

This library has been tested with:

    - Aeotec SmartThings hub V2 (Thread 1.4)

It should work with any Thread 1.4 compliant Border Router that supports commissioning using the ePSKc flow.

## Getting Admin Codes

### SmartThings

1. Open SmartThings app
2. Navigate to your Thread hub
3. Navigate to hub settings
4. Tap "Manage Thread Network"
6. Tap "Unify Thread Network" and then select "Share this hub's network to allow other Border Routers to join it"
7. Tap "Start Sharing"
8. Use the code shown within its validity period (10 minutes)

### Other Border Routers

Consult your Border Router's documentation for how to generate ephemeral commissioning codes.

## Architecture

The package consists of three main components:

### 1. HubDiscovery

mDNS/Bonjour service discovery for Thread Border Routers:

```swift
 let threadCommissioner = ThreadCommissioner()
 guard let threadHub = await self.threadCommissioner.seachForHub(timeout: 10) else {
            showAlert(title: "Search Timeout", message: "Ensure you have selected to share network in hub's app")
            return
 }
```

### 2. ThreadDTLSClient

DTLS 1.2 client with EC-JPAKE support using mbedTLS:

```swift
try await self.threadCommissioner.connectToHub(threadHub: threadHub, adminCode: adminCode)
```

### 3. ThreadCommissioner

CoAP protocol implementation for Thread Commissioner operations:

```swift
 guard let dataset = await self.threadCommissioner.getThreadDataset() else {
               showAlert(title: "Search Timeout", message: "Ensure you have selected to share network in hub's app")
               return
 }
```

## Dependencies

- **mbedTLS 3.6.4**: Embedded TLS/DTLS library with EC-JPAKE support (included as XCFramework)
- **Network.framework**: Apple's network framework for mDNS discovery
- **Security.framework**: Cryptographic operations

## Implementation Details

### Concurrency

- Uses Swift's modern concurrency (async/await)
- `@MainActor` isolation for UI-related discovery operations
- `nonisolated(unsafe)` for C library integration with manual thread safety

### Error Handling

Errors are thrown as Swift errors:

```swift
enum CommissionerError: Error {
    case connectionFailed(String)
    case petitionFailed(String)
    case datasetRequestFailed(String)
    case invalidResponse(String)
}

enum DTLSError: Error {
    case connectionFailed(String)
    case handshakeFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case invalidPSK
    case invalidAdminCode
}
```

## Limitations

- Currently supports iOS/macOS only (mbedTLS xcframework)
- Requires Thread Border Router with Thread 1.4 Commercial Commissioning support
- Admin codes are temporary (typically 5-10 minute validity)
- Single commissioner instance per application

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Licensing

**Free for personal/non‑commercial use. Paid licence required for commercial use.**

This project is dual‑licensed:

- **Non-Commercial License (default)** – Free for personal, educational, or other non-commercial use. See [LICENSE](LICENSE).
- **Commercial License** – Required for any commercial, proprietary, or closed-source use. See [LICENSE.COM](LICENSE.COM) for terms, or contact [threadcommissionerkit@gmail.com](mailto:threadcommissionerkit@gmail.com).

Typical commercial licences start at **£499 one-time** or **£349/year** including updates and support. Volume and enterprise terms available on request.

Third-party components (including mbedTLS under the Apache 2.0 licence) are listed in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## Security & Compliance Notes

- Uses **EC‑JPAKE over DTLS 1.2** (mbedTLS 3.6.4) and follows the Thread 1.4 Commercial Commissioning flow.
- Admin codes are **ephemeral**; do not log or persist them.
- Dataset materials (e.g., Network Key, PSKc) are **sensitive**; store securely (Keychain) and minimise lifetime in memory.
- You are responsible for ensuring compliance with **Thread Group** policies, local regulations, and any OEM terms of your Border Router.

## References

- [Thread 1.4 Specification](https://www.threadgroup.org/support#specifications)
- [mbedTLS Documentation](https://mbed-tls.readthedocs.io/)
- [CoAP RFC 7252](https://datatracker.ietf.org/doc/html/rfc7252)
- [Thread Commercial Commissioning](https://openthread.io/guides/border-router/external-commissioning)
