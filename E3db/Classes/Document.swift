//
//  Document.swift
//  E3db
//

import Foundation
import Swish
import Argo
import Ogra
import Curry
import Runes
import Result
import Sodium

// MARK: Offline Crypto Operations

public protocol Signable {
    // must be deterministic
    func serialized() -> String
}

public struct EncryptedDocument: Signable {
    public let clientMeta: ClientMeta
    public let encryptedData: CipherData
    public let recordSignature: String
}

public struct DecryptedDocument {
    public let clientMeta: ClientMeta
    public let data: Cleartext
    public let verified: Bool
}

public struct SignedDocument<T: Signable>: Signable {
    public let document: T
    public let signature: String

    public init(document: T, signature: String) {
        self.document  = document
        self.signature = signature
    }
}

extension Signable where Self: Ogra.Encodable {
    public func serialized() -> String {
        return encode().serialize()
    }
}

extension EncryptedDocument: Ogra.Encodable {
    public func encode() -> JSON {
        return JSON.object([
            "meta": clientMeta.encode(),
            "data": encryptedData.encode(),
            "rec_sig": recordSignature.encode()
        ])
    }
}

extension SignedDocument: Ogra.Encodable {
    public func encode() -> JSON {
        let encoded = document.serialized()
        let jsonObj = try? JSONSerialization.jsonObject(with: Data(encoded.utf8), options: [])
        return JSON.object([
            "doc": JSON(jsonObj ?? encoded),
            "sig": signature.encode()
        ])
    }
}

extension String: Signable {
    public func serialized() -> String {
        return self
    }
}

extension Client {
    private struct RecordInfo: Signable {
        let meta: ClientMeta
        let data: RecordData

        func serialized() -> String {
            return meta.serialized() + data.serialized()
        }
    }

    // Check for AK in local cache or decrypt the given EAK
    private func getLocalAk(clientId: UUID, recordType: String, eakInfo: EAKInfo) throws -> RawAccessKey {
        let cacheKey = AkCacheKey(writerId: clientId, userId: clientId, recordType: recordType)
        guard let localAk = akCache.object(forKey: cacheKey)?.rawAk ?? (try? Crypto.decrypt(eakInfo: eakInfo, clientPrivateKey: config.privateKey)) else {
            throw E3dbError.cryptoError("Failed to decrypt access key")
        }
        return localAk
    }

    public func sign<T: Signable>(document: T) throws -> SignedDocument<T> {
        guard let privSigKey = Sign.SecretKey(base64URLEncoded: config.privateSigKey),
              let signature  = Crypto.signature(doc: document, signingKey: privSigKey) else {
            throw E3dbError.cryptoError("Failed to sign document")
        }
        return SignedDocument(document: document, signature: signature)
    }

    public func verify<T>(signed: SignedDocument<T>, pubSigKey: String) throws -> Bool {
        guard let pubSigKey    = Sign.PublicKey(base64URLEncoded: pubSigKey),
              let verification = Crypto.verify(doc: signed.document, encodedSig: signed.signature, verifyingKey: pubSigKey) else {
            throw E3dbError.cryptoError("Failed to verify document")
        }
        return verification
    }

    public func encrypt(type: String, data: RecordData, eakInfo: EAKInfo, plain: PlainMeta? = nil) throws -> EncryptedDocument {
        let clientId  = config.clientId
        let meta      = ClientMeta(writerId: clientId, userId: clientId, type: type, plain: plain)
        let recInfo   = RecordInfo(meta: meta, data: data)
        let localAk   = try getLocalAk(clientId: clientId, recordType: type, eakInfo: eakInfo)
        let signed    = try sign(document: recInfo)
        let encrypted = try Crypto.encrypt(recordData: recInfo.data, ak: localAk)
        return EncryptedDocument(clientMeta: meta, encryptedData: encrypted, recordSignature: signed.signature)
    }

    public func decrypt(encryptedDoc: EncryptedDocument, eakInfo: EAKInfo, writerPubSigKey: String) throws -> DecryptedDocument {
        let meta      = encryptedDoc.clientMeta
        let localAk   = try getLocalAk(clientId: eakInfo.authorizerId, recordType: meta.type, eakInfo: eakInfo)
        let decrypted = try Crypto.decrypt(cipherData: encryptedDoc.encryptedData, ak: localAk)
        let recInfo   = RecordInfo(meta: meta, data: decrypted)
        let signed    = SignedDocument(document: recInfo, signature: encryptedDoc.recordSignature)
        let verified  = try verify(signed: signed, pubSigKey: writerPubSigKey)
        return DecryptedDocument(clientMeta: meta, data: decrypted.cleartext, verified: verified)
    }

}
