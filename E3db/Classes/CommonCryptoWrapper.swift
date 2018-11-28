//
//  CommonCryptoWrapper.swift
//  E3db
//
//  Created by Michael Lee on 11/27/18.
//  Copyright © 2018 Tozny. All rights reserved.
//
#if canImport(CommonCrypto)
import CommonCrypto
#endif
import Foundation

// Type to hold the key to decrypt using Common Crypto
public struct CCKey: Codable {
    // AES Key for symmetric encryption
    let aesKey: String
    // AES IV also for symmetric encryption
    let aesIV: String
}

// MARK: CC Utilities

struct CommonCrypto {
    
    // MARK: CC Key Generation
    
    // Sec random bytes, is this the right RNG to use
    static func generateRandomAccessKey(length: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return nil
        }
        let data = Data(bytes: bytes)
        return data
    }
    
    // Create the key and iv for aes
    static func generateCCKey() throws -> CCKey {
        guard let keyBytes = generateRandomAccessKey(length: kCCBlockSizeAES128),
              let ivBytes = generateRandomAccessKey(length: kCCBlockSizeAES128) else {
            throw E3dbError.cryptoError("CCKey Key generation failed")
        }
        return CCKey(aesKey: keyBytes.base64EncodedString(), aesIV: ivBytes.base64EncodedString())
    }
    
    // MARK: CC Crypto

    static func crypt(input: Data, operation: CCOperation, key: Data, iv: Data, algo: CCAlgorithm, options: CCOptions, blockSize: Int) throws -> Data {
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: input.count + blockSize)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)

        input.withUnsafeBytes { (rawData: UnsafePointer<UInt8>!) -> () in
            iv.withUnsafeBytes { (ivBytes: UnsafePointer<UInt8>!) in
                key.withUnsafeBytes { (keyBytes: UnsafePointer<UInt8>!) -> () in
                    status = CCCrypt(operation,                     // encrypt or decrypt
                        algo,                                       // algorithm
                        options,                                    // options (cbc/ctr)
                        keyBytes,                                   // key
                        key.count,                                  // keylength
                        ivBytes,                                    // iv
                        rawData,                                    // input
                        input.count,                                // input length
                        &outBytes,                                  // output
                        outBytes.count,                             // output length
                        &outLength)                                 // ???
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw E3dbError.cryptoError("Failed to encrypt data")
        }
        return Data(bytes: UnsafePointer<UInt8>(outBytes), count: outLength)
    }
    
    static func encrypt(rawData: Data, ccKey: CCKey) throws -> Data {
        guard let key = Data(base64Encoded: ccKey.aesKey) else {
            throw E3dbError.cryptoError("Common Crypto invalid Key")
        }
        guard let iv = Data(base64Encoded: ccKey.aesIV) else {
            throw E3dbError.cryptoError("Common Crypto invalid IV")
        }
        return try crypt(input: rawData, operation: CCOperation(kCCEncrypt), key: key, iv: iv, algo: CCAlgorithm(kCCAlgorithmAES128), options: CCOptions(kCCOptionPKCS7Padding | kCCModeCBC), blockSize: kCCBlockSizeAES128)
    }
    
    static func decrypt(encryptedData: Data, ccKey: CCKey) throws -> Data {
        guard let key = Data(base64Encoded: ccKey.aesKey) else {
            throw E3dbError.cryptoError("Common Crypto invalid Key")
        }
        guard let iv = Data(base64Encoded: ccKey.aesIV) else {
            throw E3dbError.cryptoError("Common Crypto invalid IV")
        }
        return try crypt(input: encryptedData, operation: CCOperation(kCCDecrypt), key: key, iv: iv, algo: CCAlgorithm(kCCAlgorithmAES128), options: CCOptions(kCCOptionPKCS7Padding | kCCModeCBC), blockSize: kCCBlockSizeAES128)
    }
    
}
