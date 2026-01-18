import Foundation

#if os(Windows)
import WinSDK

// MARK: - BCrypt Constants (not imported from headers due to wide string macros)

private let BCRYPT_AES_ALGORITHM: [WCHAR] = Array("AES".utf16) + [0]
private let BCRYPT_CHAIN_MODE_GCM: [WCHAR] = Array("ChainingModeGCM".utf16) + [0]
private let BCRYPT_CHAINING_MODE: [WCHAR] = Array("ChainingMode".utf16) + [0]
private let BCRYPT_AUTH_TAG_LENGTH: [WCHAR] = Array("AuthTagLength".utf16) + [0]

/// Windows Data Protection API (DPAPI) wrapper for decrypting protected data.
public enum WindowsDPAPI {
    /// Error types for DPAPI operations.
    public enum Error: Swift.Error, LocalizedError {
        case decryptionFailed(code: UInt32)
        case invalidData
        case memoryAllocationFailed

        public var errorDescription: String? {
            switch self {
            case let .decryptionFailed(code):
                return "DPAPI decryption failed with error code: \(code)"
            case .invalidData:
                return "Invalid encrypted data format"
            case .memoryAllocationFailed:
                return "Memory allocation failed during decryption"
            }
        }
    }

    /// Decrypts data that was encrypted using Windows DPAPI.
    /// - Parameter encryptedData: The DPAPI-encrypted data blob
    /// - Returns: The decrypted data
    /// - Throws: `Error` if decryption fails
    public static func decrypt(_ encryptedData: Data) throws -> Data {
        var inputBlob = DATA_BLOB()
        var outputBlob = DATA_BLOB()

        var encryptedBytes = [UInt8](encryptedData)

        return try encryptedBytes.withUnsafeMutableBufferPointer { buffer in
            inputBlob.cbData = DWORD(buffer.count)
            inputBlob.pbData = buffer.baseAddress

            // Call CryptUnprotectData
            let success = CryptUnprotectData(
                &inputBlob,    // pDataIn
                nil,           // ppszDataDescr (optional)
                nil,           // pOptionalEntropy (none)
                nil,           // pvReserved (must be NULL)
                nil,           // pPromptStruct (no UI)
                0,             // dwFlags
                &outputBlob    // pDataOut
            )

            guard success else {
                let errorCode = GetLastError()
                throw Error.decryptionFailed(code: errorCode)
            }

            guard outputBlob.cbData > 0, outputBlob.pbData != nil else {
                throw Error.invalidData
            }

            // Copy output data
            let result = Data(bytes: outputBlob.pbData!, count: Int(outputBlob.cbData))

            // Free the output buffer allocated by Windows
            LocalFree(outputBlob.pbData)

            return result
        }
    }
}

/// AES-256-GCM decryption for Chromium cookie values.
public enum WindowsAESGCM {
    /// Error types for AES-GCM operations.
    public enum Error: Swift.Error, LocalizedError {
        case invalidKeyLength
        case invalidNonceLength
        case invalidCiphertext
        case decryptionFailed(code: Int32)
        case algorithmNotAvailable
        case openAlgorithmFailed(code: Int32)
        case generateSymmetricKeyFailed(code: Int32)
        case setPropertyFailed(code: Int32)

        public var errorDescription: String? {
            switch self {
            case .invalidKeyLength:
                return "Invalid AES key length (expected 32 bytes)"
            case .invalidNonceLength:
                return "Invalid nonce length (expected 12 bytes)"
            case .invalidCiphertext:
                return "Invalid ciphertext format"
            case let .decryptionFailed(code):
                return "AES-GCM decryption failed with status: \(code)"
            case .algorithmNotAvailable:
                return "AES-GCM algorithm not available"
            case let .openAlgorithmFailed(code):
                return "Failed to open AES-GCM algorithm: \(code)"
            case let .generateSymmetricKeyFailed(code):
                return "Failed to generate symmetric key: \(code)"
            case let .setPropertyFailed(code):
                return "Failed to set algorithm property: \(code)"
            }
        }
    }

    /// Decrypts AES-256-GCM encrypted data.
    /// - Parameters:
    ///   - ciphertext: The encrypted data (includes 12-byte nonce prefix and 16-byte auth tag suffix)
    ///   - key: The 32-byte AES-256 key
    /// - Returns: The decrypted plaintext
    /// - Throws: `Error` if decryption fails
    public static func decrypt(ciphertext: Data, key: Data) throws -> Data {
        guard key.count == 32 else {
            throw Error.invalidKeyLength
        }

        // Chromium format: nonce (12 bytes) + encrypted_data + auth_tag (16 bytes)
        guard ciphertext.count > 12 + 16 else {
            throw Error.invalidCiphertext
        }

        let nonce = ciphertext.prefix(12)
        let authTag = ciphertext.suffix(16)
        let encryptedPayload = ciphertext.dropFirst(12).dropLast(16)

        return try decryptWithBCrypt(
            ciphertext: Data(encryptedPayload),
            nonce: Data(nonce),
            authTag: Data(authTag),
            key: key
        )
    }

    /// Decrypts using Windows BCrypt API.
    private static func decryptWithBCrypt(
        ciphertext: Data,
        nonce: Data,
        authTag: Data,
        key: Data
    ) throws -> Data {
        var hAlgorithm: BCRYPT_ALG_HANDLE?
        var hKey: BCRYPT_KEY_HANDLE?

        defer {
            if let hKey = hKey {
                BCryptDestroyKey(hKey)
            }
            if let hAlgorithm = hAlgorithm {
                BCryptCloseAlgorithmProvider(hAlgorithm, 0)
            }
        }

        // Open the AES algorithm provider
        var aesAlg = BCRYPT_AES_ALGORITHM
        var status = aesAlg.withUnsafeMutableBufferPointer { algPtr in
            BCryptOpenAlgorithmProvider(
                &hAlgorithm,
                algPtr.baseAddress,
                nil,
                0
            )
        }
        guard status == 0 else {
            throw Error.openAlgorithmFailed(code: status)
        }

        // Set chaining mode to GCM
        var gcmMode = BCRYPT_CHAIN_MODE_GCM
        var chainingMode = BCRYPT_CHAINING_MODE
        let gcmModeSize = ULONG(gcmMode.count * MemoryLayout<WCHAR>.size)
        status = chainingMode.withUnsafeMutableBufferPointer { propPtr in
            gcmMode.withUnsafeMutableBufferPointer { valuePtr in
                BCryptSetProperty(
                    hAlgorithm,
                    propPtr.baseAddress,
                    UnsafeMutablePointer<UInt8>(OpaquePointer(valuePtr.baseAddress)),
                    gcmModeSize,
                    0
                )
            }
        }
        guard status == 0 else {
            throw Error.setPropertyFailed(code: status)
        }

        // Generate the symmetric key
        var keyBytes = [UInt8](key)
        status = keyBytes.withUnsafeMutableBufferPointer { keyPtr in
            BCryptGenerateSymmetricKey(
                hAlgorithm,
                &hKey,
                nil,
                0,
                keyPtr.baseAddress,
                ULONG(keyPtr.count),
                0
            )
        }
        guard status == 0 else {
            throw Error.generateSymmetricKeyFailed(code: status)
        }

        // Prepare for decryption
        var nonceBytes = [UInt8](nonce)
        var authTagBytes = [UInt8](authTag)
        var ciphertextBytes = [UInt8](ciphertext)

        // Allocate output buffer (same size as ciphertext for GCM)
        var plaintext = [UInt8](repeating: 0, count: ciphertextBytes.count)
        var plaintextLength: ULONG = 0

        // Prepare authenticated cipher mode info
        var authInfo = BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO()
        authInfo.cbSize = ULONG(MemoryLayout<BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO>.size)
        authInfo.dwInfoVersion = 1  // BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO_VERSION

        status = nonceBytes.withUnsafeMutableBufferPointer { noncePtr in
            authTagBytes.withUnsafeMutableBufferPointer { tagPtr in
                ciphertextBytes.withUnsafeMutableBufferPointer { ctPtr in
                    plaintext.withUnsafeMutableBufferPointer { ptPtr in
                        authInfo.pbNonce = noncePtr.baseAddress
                        authInfo.cbNonce = ULONG(noncePtr.count)
                        authInfo.pbTag = tagPtr.baseAddress
                        authInfo.cbTag = ULONG(tagPtr.count)
                        authInfo.pbAuthData = nil
                        authInfo.cbAuthData = 0
                        authInfo.pbMacContext = nil
                        authInfo.cbMacContext = 0
                        authInfo.cbAAD = 0
                        authInfo.cbData = 0
                        authInfo.dwFlags = 0

                        return BCryptDecrypt(
                            hKey,
                            ctPtr.baseAddress,
                            ULONG(ctPtr.count),
                            &authInfo,
                            nil,
                            0,
                            ptPtr.baseAddress,
                            ULONG(ptPtr.count),
                            &plaintextLength,
                            0
                        )
                    }
                }
            }
        }
        guard status == 0 else {
            throw Error.decryptionFailed(code: status)
        }

        return Data(plaintext.prefix(Int(plaintextLength)))
    }
}

#endif
