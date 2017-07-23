//
//  Crypto.swift
//  E3db
//

import Foundation
import Sodium

enum CryptoError {
    case keyGen
}

typealias AccessKey          = Box.SecretKey
typealias EncryptedAccessKey = String

struct Crypto {
    typealias SecretBoxCypherNonce = (authenticatedCipherText: Data, nonce: SecretBox.Nonce)
    typealias BoxCypherNonce       = (authenticatedCipherText: Data, nonce: Box.Nonce)

    fileprivate static let sodium = Sodium()!
}

// MARK: Utilities
extension Crypto {
    static func generateKeyPair() -> Box.KeyPair? {
        return sodium.box.keyPair()
    }

    static func generateAccessKey() -> AccessKey? {
        return sodium.randomBytes.buf(length: sodium.box.SecretKeyBytes)
    }

    static func b64Join(_ cyphertexts: Data...) -> String {
        return cyphertexts.map { $0.base64URLEncodedString() }.joined(separator: ".")
    }
}

// MARK: Access Key Crypto
extension Crypto {

    static func encrypt(accessKey: AccessKey, readerClientKey: ClientKey, authorizerPrivKey: Box.SecretKey) -> EncryptedAccessKey? {
        return Box.PublicKey(base64URLEncoded: readerClientKey.curve25519)
            .flatMap { sodium.box.seal(message: accessKey, recipientPublicKey: $0, senderSecretKey: authorizerPrivKey) }
            .map { (eakData: BoxCypherNonce) in b64Join(eakData.authenticatedCipherText, eakData.nonce) }
//        guard let readerPubKey = Box.PublicKey(base64URLEncoded: readerClientKey.curve25519)
//             else {
//            return nil
//        }
//        let eakData: BoxCypherNonce? = sodium.box.seal(message: accessKey, recipientPublicKey: readerPubKey, senderSecretKey: authorizerPrivKey)
//        let eak = eakData.map { b64Join($0.authenticatedCipherText, $0.nonce) }
//        let eak = b64Join(eakData.authenticatedCipherText, eakData.nonce)
//        return eak
    }

    static func decrypt(eakResponse: EAKResponse, clientPrivateKey: String) throws -> AccessKey {
        let split = eakResponse.eak.split(separator: ".", maxSplits: 1)
            .map(String.init)
            .flatMap { Data(base64URLEncoded: $0) }

        guard split.count == 2 else {
            throw E3dbError.cryptoError("Invalid access key format")
        }

        guard let authorizerPubKey = Box.PublicKey(base64URLEncoded: eakResponse.authorizerPublicKey.curve25519),
            let privKey = Box.SecretKey(base64URLEncoded: clientPrivateKey),
            let ak = sodium.box.open(authenticatedCipherText: split[0], senderPublicKey: authorizerPubKey, recipientSecretKey: privKey, nonce: split[1]) else {
            throw E3dbError.cryptoError("Failed to decrypt access key")
        }

        return ak
    }
}

// MARK: Record Data Crypto
extension Crypto {

    private static func generateSecretKey() throws -> SecretBox.Key {
        guard let secretKey = sodium.secretBox.key() else {
            throw E3dbError.cryptoError("Failed to generate secret box key.")
        }
        return secretKey
    }

    private static func encrypt(value: Data, key: SecretBox.Key) throws -> SecretBoxCypherNonce {
        guard let cypher: SecretBoxCypherNonce = sodium.secretBox.seal(message: value, secretKey: key) else {
            throw E3dbError.cryptoError("Failed to encrypt value.")
        }
        return cypher
    }

    static func encrypt(recordData: RecordData, ak: AccessKey) throws -> CypherData {
        var encrypted = CypherData()
        for (key, value) in recordData {
            let dk          = try generateSecretKey()
            let (ef, efN)   = try encrypt(value: value, key: dk)
            let (edk, edkN) = try encrypt(value: dk, key: ak)
            encrypted[key]  = b64Join(edk, edkN, ef, efN)
        }
        return encrypted
    }
}
