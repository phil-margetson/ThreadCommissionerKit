//
//  ThreadDTLSClient.swift
//
//  DTLS client for Thread 1.4 Admin Code (ePSKc) commissioning via EC-JPAKE

import Foundation
import CThreadCommissioner

enum DTLSError: Error, LocalizedError {
    case connectionFailed(String)
    case handshakeFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case invalidPSK
    case invalidAdminCode
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message),
             .handshakeFailed(let message),
             .sendFailed(let message),
             .receiveFailed(let message):
            return message
        case .invalidPSK:
            return "PSK from the hub was invalid."
        case .invalidAdminCode:
            return "Admin code must be 9 digits."
        }
    }
}

enum DTLSLoggingLevel: Int32 {
    case noDebug = 0
    case error = 1
    case info = 3
    case verbose = 4
}

nonisolated(unsafe) class ThreadDTLSClient {

    private let ssl: UnsafeMutablePointer<mbedtls_ssl_context>
    private let config: UnsafeMutablePointer<mbedtls_ssl_config>
    private let entropy: UnsafeMutablePointer<mbedtls_entropy_context>
    private let ctrdrbg: UnsafeMutablePointer<mbedtls_ctr_drbg_context>
    private let timer: UnsafeMutablePointer<mbedtls_timing_delay_context>
    private let serverfd: UnsafeMutablePointer<mbedtls_net_context>

    // Keep ciphersuites array alive for the lifetime of the config
    private var ciphersuites: [Int32] = []

    // Track if connection is active
    private var isConnected = false
    private var hasSetupSSL = false

    init() {
        // Allocate mbedTLS contexts on the heap
        ssl = UnsafeMutablePointer.allocate(capacity: 1)
        config = UnsafeMutablePointer.allocate(capacity: 1)
        entropy = UnsafeMutablePointer.allocate(capacity: 1)
        ctrdrbg = UnsafeMutablePointer.allocate(capacity: 1)
        timer = UnsafeMutablePointer.allocate(capacity: 1)
        serverfd = UnsafeMutablePointer.allocate(capacity: 1)

        mbedtls_ssl_init(ssl)
        mbedtls_ssl_config_init(config)
        mbedtls_ctr_drbg_init(ctrdrbg)
        mbedtls_entropy_init(entropy)
        mbedtls_net_init(serverfd)
    }

    deinit {
        // Clean up mbedTLS contexts
        mbedtls_net_free(serverfd)
        mbedtls_entropy_free(entropy)
        mbedtls_ctr_drbg_free(ctrdrbg)
        mbedtls_ssl_config_free(config)
        mbedtls_ssl_free(ssl)

        // Deallocate heap memory
        ssl.deallocate()
        config.deallocate()
        entropy.deallocate()
        ctrdrbg.deallocate()
        timer.deallocate()
        serverfd.deallocate()
    }
    
    func updateLoggingLevel(_ level: DTLSLoggingLevel) {
        mbedtls_debug_set_threshold(level.rawValue)
    }

    /// Connect to Thread device using DTLS with EC-JPAKE and Admin Code
    nonisolated(nonsending) func connect(host: String, port: UInt16, adminCode: String) async throws {
        let trimmedAdmin = adminCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAdmin.range(of: "^[0-9]{6,12}$", options: .regularExpression) != nil else {
            throw DTLSError.invalidAdminCode
        }
        print("🔐 Admin Code (ASCII): \(trimmedAdmin)")

        // Ensure any previous session/socket state is cleared before reconnecting
        mbedtls_net_free(serverfd)
        mbedtls_net_init(serverfd)
        if hasSetupSSL {
            let resetResult = mbedtls_ssl_session_reset(ssl)
            guard resetResult == 0 else {
                throw DTLSError.connectionFailed("Session reset failed: \(resetResult)")
            }
        }

        // Initialize RNG
        let pers = "dtls_client"
        var ret = pers.withCString { persPtr in
            mbedtls_ctr_drbg_seed(ctrdrbg, mbedtls_entropy_func, entropy,
                                  persPtr, strlen(persPtr))
        }

        guard ret == 0 else {
            throw DTLSError.connectionFailed("RNG init failed: \(ret)")
        }
        print("✅ RNG initialized")

        // Connect to server
        print("🌐 Attempting UDP connection to \(host):\(port)...")
        ret = host.withCString { hostPtr in
            String(port).withCString { portPtr in
                mbedtls_net_connect(serverfd, hostPtr, portPtr, MBEDTLS_NET_PROTO_UDP)
            }
        }

        guard ret == 0 else {
            var errorBuf = [Int8](repeating: 0, count: 100)
            mbedtls_strerror(ret, &errorBuf, 100)
            let errorMsg = String(cString: errorBuf)
            throw DTLSError.connectionFailed("Connection failed: \(ret) - \(errorMsg)")
        }
        print("✅ UDP socket connected to \(host):\(port)")

        // Setup SSL config
        ret = mbedtls_ssl_config_defaults(config,
                                          MBEDTLS_SSL_IS_CLIENT,
                                          MBEDTLS_SSL_TRANSPORT_DATAGRAM,
                                          MBEDTLS_SSL_PRESET_DEFAULT)

        guard ret == 0 else {
            throw DTLSError.connectionFailed("SSL config failed: \(ret)")
        }
        print("✅ SSL config set")

        // Disable certificate verification completely for EC-JPAKE mode
        mbedtls_ssl_conf_authmode(config, MBEDTLS_SSL_VERIFY_NONE)
        print("✅ Disabled certificate verification")

        // Force PSK-only ciphersuites for Thread Commissioner
        // Thread typically uses TLS-PSK-WITH-AES-128-CCM-8
        self.ciphersuites = [
            MBEDTLS_TLS_ECJPAKE_WITH_AES_128_CCM_8,
            0  // Terminator
        ]
        mbedtls_ssl_conf_ciphersuites(config, self.ciphersuites)
        print("✅ Forced EC-JPAKE ciphersuite (AES-128-CCM-8)")

        // Enable debug output
        mbedtls_ssl_conf_dbg(config, { (ctx, level, file, line, msg) in
            if let msg = msg, let cStr = String(validatingUTF8: msg) {
                print("mbedTLS[\(level)]: \(cStr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }, nil)
        // mbedtls_debug_set_threshold(3)  // Verbose debug
        print("✅ Debug logging enabled")

        mbedtls_ssl_conf_rng(config, mbedtls_ctr_drbg_random, ctrdrbg)
        print("✅ RNG callback set")
        mbedtls_ssl_conf_read_timeout(config, 10000) // 10 second timeout

        ret = mbedtls_ssl_setup(ssl, config)
        guard ret == 0 else {
            throw DTLSError.connectionFailed("SSL setup failed: \(ret)")
        }
        hasSetupSSL = true
        print("✅ SSL context setup")

        // Set EC-JPAKE password = admin code ASCII (no hex, no PBKDF2)
        let rcSetPw = trimmedAdmin.withCString { cstr -> Int32 in
            let pw = UnsafePointer<UInt8>(OpaquePointer(cstr))
            return mbedtls_ssl_set_hs_ecjpake_password(ssl, pw, strlen(cstr))
        }
        guard rcSetPw == 0 else {
            throw DTLSError.connectionFailed("Failed to set EC-JPAKE password: \(rcSetPw)")
        }
        print("✅ EC-JPAKE password set from Admin Code")

        mbedtls_ssl_set_bio(ssl, serverfd, mbedtls_net_send, mbedtls_net_recv, mbedtls_net_recv_timeout)
        mbedtls_ssl_set_timer_cb(ssl, timer, mbedtls_timing_set_delay, mbedtls_timing_get_delay)
        print("🤝 Starting DTLS handshake...")

        // Perform handshake with timeout
        var handshakeAttempts = 0
        let maxAttempts = 100
        repeat {
            ret = mbedtls_ssl_handshake(ssl)
            handshakeAttempts += 1
            if ret != 0 && ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE {
                print("⚠️ Handshake attempt \(handshakeAttempts) failed with code: \(ret)")
            }
            if ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE {
                print("   ... waiting (attempt \(handshakeAttempts))")
            }
            if handshakeAttempts >= maxAttempts {
                print("❌ Handshake timeout after \(maxAttempts) attempts")
                break
            }
        } while ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE

        guard ret == 0 else {
            var errorBuf = [Int8](repeating: 0, count: 100)
            mbedtls_strerror(ret, &errorBuf, 100)
            let errorMsg = String(cString: errorBuf)
            print("❌ Handshake failed after \(handshakeAttempts) attempts")
            print("   Error code: \(ret) (0x\(String(ret, radix: 16)))")
            print("   Error message: \(errorMsg)")
            throw DTLSError.handshakeFailed("Handshake failed: \(ret) - \(errorMsg)")
        }

        print("✅ DTLS Handshake successful!")
        isConnected = true
    }

    /// Send data over DTLS connection
    func send(_ data: Data) throws {
        let ret = data.withUnsafeBytes { dataPtr in
            mbedtls_ssl_write(ssl, dataPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), data.count)
        }

        guard ret >= 0 else {
            throw DTLSError.sendFailed("Send failed: \(ret)")
        }
    }

    /// Receive data from DTLS connection
    func receive(maxLength: Int = 4096) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let ret = mbedtls_ssl_read(ssl, &buffer, maxLength)

        guard ret >= 0 else {
            throw DTLSError.receiveFailed("Receive failed: \(ret)")
        }

        return Data(buffer.prefix(Int(ret)))
    }

    /// Close DTLS connection
    func close() {
        mbedtls_net_free(serverfd)
        mbedtls_net_init(serverfd)
        if hasSetupSSL {
            _ = mbedtls_ssl_session_reset(ssl)
        }

        guard isConnected else {
            print("⚠️ Connection already closed")
            return
        }

        // Just mark as closed - deinit will clean up resources
        // Calling mbedtls_ssl_close_notify can crash if SSL context is corrupted
        isConnected = false
        print("✅ Connection marked for cleanup")
    }
}

// swiftlint:enable all
