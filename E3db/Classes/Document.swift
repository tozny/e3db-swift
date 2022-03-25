//
//  Document.swift
//  E3db
//

import Foundation
import ToznySodium
import ToznySwish

// MARK: Offline Crypto Operations

/// Protocol to allow types to be cryptographically
/// signed and verified. Requires serialization to
/// be deterministic.
public protocol Signable {

    /// Provides a reproducible string representation
    /// of the data to sign and verify. Requires the
    /// serialization to be deterministic -- i.e. types
    /// such as `Dictionary` and `Set` must be serialized
    /// in a reproducible order.
    ///
    /// - Returns: Reproducible string representation of the type
    func serialized() -> String
}

/// Data type to hold encrypted data and related info
public struct EncryptedDocument: Codable, Signable {

    /// Metadata produced by this client about this document
    public let clientMeta: ClientMeta

    /// The ciphertext after it has been encrypted,
    /// the keys remain unencrypted
    public let encryptedData: CipherData

    /// A cryptographic signature of the `clientMeta`
    /// and the cleartext data before it was encrypted
    public let recordSignature: String

    enum CodingKeys: String, CodingKey {
        case clientMeta      = "meta"
        case encryptedData   = "data"
        case recordSignature = "rec_sig"
    }

    public func serialized() -> String {
        return [
            CodingKeys.clientMeta.rawValue: AnySignable(clientMeta),
            CodingKeys.encryptedData.rawValue: AnySignable(encryptedData),
            CodingKeys.recordSignature.rawValue: AnySignable(recordSignature)
        ].serialized()
    }
}

/// Data type to hold the verified, unencrypted data and related info
public struct DecryptedDocument {

    /// Metadata produced by this client about this document
    public let clientMeta: ClientMeta

    /// The plaintext information where both keys and values
    /// are unencrypted
    public let data: Cleartext
}

/// A wrapper object around a given data type and its
/// cryptographic signature. Note that document remains unchanged
public struct SignedDocument<T: Signable>: Signable {

    /// A data type that conforms to the `Signable` protocol
    /// (i.e. it is deterministically serializable)
    public let document: T

    /// The cryptographic signature over the serialized document
    public let signature: String

    enum CodingKeys: String, CodingKey {
        case document  = "doc"
        case signature = "sig"
    }

    /// Initializer to manually create `SignedDocument` types.
    ///
    /// - Parameters:
    ///   - document: A data type that conforms to the `Signable` protocol
    ///   - signature: The cryptographic signature over the serialized document
    public init(document: T, signature: String) {
        self.document  = document
        self.signature = signature
    }

    public func serialized() -> String {
        return [
            CodingKeys.document.rawValue: AnySignable(document),
            CodingKeys.signature.rawValue: AnySignable(signature)
        ].serialized()
    }
}

// Container for signing and
// verification operations
struct DocInfo: Encodable, Signable {
    let meta: ClientMeta
    let data: RecordData

    // convention for serializing document is
    // `serialized(ClientMeta) || serialized(CleartextData)`
    func serialized() -> String {
        return meta.serialized() + data.serialized()
    }
}

extension Client {

    // Check for AK in local cache or decrypt the given EAK
    private func getLocalAk(clientId: UUID, recordType: String, eakInfo: EAKInfo) throws -> RawAccessKey {
        let cacheKey = AkCacheKey(writerId: clientId, userId: clientId, recordType: recordType)
        guard let localAk = akCache.object(forKey: cacheKey)?.rawAk ?? (try? Crypto.decrypt(eakInfo: eakInfo, clientPrivateKey: config.privateKey)) else {
            throw E3dbError.cryptoError("Failed to decrypt access key")
        }
        return localAk
    }

    /// Use the client's private signing key to create a cryptographic signature
    /// over the serialized representation of the given document.
    ///
    /// - Note: this does not change the document at all (e.g. the values are _not_ encrypted).
    ///
    /// - Parameter document: A data type that conforms to the `Signable` protocol
    /// - Returns: A wrapper object around a given data type and its cryptographic signature
    /// - Throws: `E3dbError.cryptoError` if the operation failed
    public func sign<T: Signable>(document: T) throws -> SignedDocument<T> {
        guard let privSigKey = Sign.SecretKey(base64UrlEncoded: config.privateSigKey),
              let signature  = Crypto.signature(doc: document, signingKey: privSigKey) else {
            throw E3dbError.cryptoError("Failed to sign document")
        }
        return SignedDocument(document: document, signature: signature)
    }
    
    public static func sign<T: Signable>(document: T, privateKey: String) throws -> SignedDocument<T> {
        guard let privSigKey = Sign.SecretKey(base64UrlEncoded: privateKey),
              let signature  = Crypto.signature(doc: document, signingKey: privSigKey) else {
            throw E3dbError.cryptoError("Failed to sign document")
        }
        return SignedDocument(document: document, signature: signature)
    }

    /// Verify message authenticity. Confirm that the signature for the `SignedDocument` was
    /// created by the client identified by the given public key, for the document provided.
    ///
    /// - Parameters:
    ///   - signed: A wrapper object around a given data type and its cryptographic signature
    ///   - pubSigKey: The public portion of the key used to create the signature in the `signed` document
    /// - Returns: Whether the document was signed by the creator of the given public key
    /// - Throws: `E3dbError.cryptoError` if the operation failed
    public func verify<T>(signed: SignedDocument<T>, pubSigKey: String) throws -> Bool {
        guard let pubSigKey    = Sign.PublicKey(base64UrlEncoded: pubSigKey),
              let verification = Crypto.verify(doc: signed.document, encodedSig: signed.signature, verifyingKey: pubSigKey) else {
            throw E3dbError.cryptoError("Failed to verify document")
        }
        return verification
    }

    /// Create a document to hold data signed for authenticicy and encrypted for confidentiality.
    /// The resulting document also holds info related to the author, type of data, and any additional
    /// metadata kept in cleartext.
    ///
    /// - Parameters:
    ///   - type: The kind of data this document represents
    ///   - data: The cleartext data to be encrypted
    ///   - eakInfo: The encrypted access key information used for the encryption operation
    ///   - plain: Additional metadata to be included -- remains unencrypted.
    /// - Returns: Data type to hold encrypted data and related info
    /// - Throws: `E3dbError.cryptoError` if the operation failed
    public func encrypt(type: String, data: RecordData, eakInfo: EAKInfo, plain: PlainMeta? = nil) throws -> EncryptedDocument {
        let clientId  = config.clientId
        let meta      = ClientMeta(writerId: clientId, userId: clientId, type: type, plain: plain, fileMeta: nil)
        let docInfo   = DocInfo(meta: meta, data: data)
        let signed    = try sign(document: docInfo)
        let localAk   = try getLocalAk(clientId: clientId, recordType: type, eakInfo: eakInfo)
        let encrypted = try Crypto.encrypt(recordData: docInfo.data, ak: localAk)
        return EncryptedDocument(clientMeta: meta, encryptedData: encrypted, recordSignature: signed.signature)
    }

    /// Create a document to hold the original plaintext data from the given encrypted format.
    /// The resulting document also holds info related to the author, type of data, and any additional
    /// metadata kept in cleartext. The input document is also verified for authenticiy with the given
    /// public signing key, and throws an error if verification fails.
    ///
    /// - Parameters:
    ///   - encryptedDoc: Data type to hold encrypted data and related info
    ///   - eakInfo: The encrypted access key information used for the decryption operation
    /// - Returns: Data type to hold the unencrypted data and related info
    /// - Throws: `E3dbError.cryptoError` if the decrypt operation fails, or if the document fails verification
    public func decrypt(encryptedDoc: EncryptedDocument, eakInfo: EAKInfo) throws -> DecryptedDocument {
        guard let sigKey = eakInfo.signerSigningKey?.ed25519 else {
            throw E3dbError.cryptoError("EAKInfo has no signing key")
        }
        let meta      = encryptedDoc.clientMeta
        let localAk   = try getLocalAk(clientId: eakInfo.authorizerId, recordType: meta.type, eakInfo: eakInfo)
        let decrypted = try Crypto.decrypt(cipherData: encryptedDoc.encryptedData, ak: localAk)
        let docInfo   = DocInfo(meta: meta, data: decrypted)
        let signed    = SignedDocument(document: docInfo, signature: encryptedDoc.recordSignature)
        guard try verify(signed: signed, pubSigKey: sigKey) else {
            throw E3dbError.cryptoError("Document failed verification")
        }
        return DecryptedDocument(clientMeta: meta, data: decrypted.cleartext)
    }

}
