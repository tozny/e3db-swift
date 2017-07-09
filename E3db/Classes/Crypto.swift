//
//  Crypto.swift
//  E3db
//

import Foundation
import Sodium

enum CryptoError {
    case keyGen
}

typealias AccessKey = Box.SecretKey

struct Crypto {

    typealias SecretBoxCypherNonce = (authenticatedCipherText: Data, nonce: SecretBox.Nonce)
    typealias BoxCypherNonce       = (authenticatedCipherText: Data, nonce: Box.Nonce)

    private static let sodium = Sodium()!

    static func generateKeyPair() throws -> Box.KeyPair {
        guard let keyPair = sodium.box.keyPair() else {
            throw E3dbError.cryptoError("Failed to generate box key pair.")
        }
        return keyPair
    }

    // TODO: Actually, get/put accessKey, using a cache if necessary
    static func generateAccessKey() throws -> AccessKey {
        guard let ak = sodium.randomBytes.buf(length: sodium.box.SecretKeyBytes) else {
            throw E3dbError.cryptoError("Failed to generate access key.")
        }
        return ak
    }

    static func generateSecretKey() throws -> SecretBox.Key {
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

    static func encrypt(accessKey: AccessKey, clientKey: ClientKey, authorizerPrivKey: Box.SecretKey) throws -> BoxCypherNonce {
        guard let readerPubKey = Data(base64URLEncoded: clientKey.curve25519),
            let cypher: BoxCypherNonce = sodium.box.seal(message: accessKey, recipientPublicKey: readerPubKey, senderSecretKey: authorizerPrivKey) else {
            throw E3dbError.cryptoError("Failed to encrypt access key")
        }
        return cypher
    }

    static func decrypt(eakResponse: EAKResponse, clientPrivateKey: String) throws -> AccessKey {
        let split = eakResponse.eak.split(separator: ".", maxSplits: 1)
            .map(String.init)
            .flatMap { Data(base64URLEncoded: $0) }

        guard split.count == 2 else {
            throw E3dbError.cryptoError("Invalid access key format")
        }

        guard let authorizerPubKey = Data(base64URLEncoded: eakResponse.authorizerPublicKey.curve25519),
            let privKey = Data(base64URLEncoded: clientPrivateKey),
            let ak = sodium.box.open(authenticatedCipherText: split[0], senderPublicKey: authorizerPubKey, recipientSecretKey: privKey, nonce: split[1]) else {
            throw E3dbError.cryptoError("Failed to decrypt access key")
        }

        return ak
    }

//    static func generateNonce() -> Box.Nonce {
//        return sodium.box.nonce()
//    }

    static func b64Join(_ chunks: Data...) -> String {
        return chunks.map { $0.base64URLEncodedString() }.joined(separator: ".")
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
