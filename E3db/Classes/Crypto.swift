//
//  Crypto.swift
//  E3db
//

#if canImport(CommonCrypto)
import CommonCrypto
#endif
import Foundation
import Sodium
import Security

typealias RawAccessKey       = SecretBox.Key
typealias EncryptedAccessKey = String

public struct Crypto {
    typealias SecretBoxCipherNonce   = (authenticatedCipherText: Bytes, nonce: SecretBox.Nonce)
    typealias BoxCipherNonce         = (authenticatedCipherText: Bytes, nonce: Box.Nonce)
    fileprivate static let sodium    = Sodium()
    fileprivate static let version   = "3"
    fileprivate static let blockSize = 65_536
}

// MARK: Base64url Encoding / Decoding

extension Crypto {
    static func base64UrlEncoded(bytes: Bytes) throws -> String {
        guard let encoded = sodium.utils.bin2base64(bytes, variant: .URLSAFE_NO_PADDING) else {
            throw E3dbError.cryptoError("Failed to encode data")
        }
        return encoded
    }

    static func base64UrlDecoded(string: String) throws -> Bytes {
        guard let decoded = sodium.utils.base642bin(string, variant: .URLSAFE_NO_PADDING) else {
            throw E3dbError.cryptoError("Failed to decode data")
        }
        return decoded
    }
}

// MARK: Utilities

extension Crypto {
    static func generateKeyPair() -> Box.KeyPair? {
        return sodium.box.keyPair()
    }

    static func randomBytes(length: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != 0 {
            throw E3dbError.cryptoError("Failed to generate secure random number \(status)")
        }
        return try Crypto.base64UrlEncoded(bytes: bytes)
    }

    static func generateSigningKeyPair() -> Sign.KeyPair? {
        return sodium.sign.keyPair()
    }

    static func generateAccessKey() -> RawAccessKey? {
        return sodium.secretBox.key()
    }

    static func b64Join(_ ciphertexts: Bytes...) throws -> String {
        return try ciphertexts.map(base64UrlEncoded).joined(separator: ".")
    }

    static func b64SplitData(_ value: String) throws -> (Bytes, Bytes, Bytes, Bytes)? {
        let split = try b64Split(value)
        guard split.count == 4 else { return nil }
        return (split[0], split[1], split[2], split[3])
    }

    static func b64SplitEak(_ value: String) throws -> (Bytes, Bytes)? {
        let split = try b64Split(value)
        guard split.count == 2 else { return nil }
        return (split[0], split[1])
    }

    private static func b64Split(_ value: String) throws -> [Bytes] {
        return try value.components(separatedBy: ".").map(base64UrlDecoded)
    }
}

// MARK: Access Key Crypto

extension Crypto {

    static func encrypt(accessKey: RawAccessKey, readerClientKey: ClientKey, authorizerPrivKey: Box.SecretKey) -> EncryptedAccessKey? {
        return Box.PublicKey(base64UrlEncoded: readerClientKey.curve25519)
            .flatMap { sodium.box.seal(message: accessKey, recipientPublicKey: $0, senderSecretKey: authorizerPrivKey) }
            .flatMap { (eakData: BoxCipherNonce) in try? b64Join(eakData.authenticatedCipherText, eakData.nonce) }
    }

    static func decrypt(eakInfo: EAKInfo, clientPrivateKey: String) throws -> RawAccessKey {
        guard let (eak, eakN) = try b64SplitEak(eakInfo.eak) else {
            throw E3dbError.cryptoError("Invalid access key format")
        }

        guard let authorizerPubKey = Box.PublicKey(base64UrlEncoded: eakInfo.authorizerPublicKey.curve25519),
              let privKey = Box.SecretKey(base64UrlEncoded: clientPrivateKey),
              let ak = sodium.box.open(authenticatedCipherText: eak, senderPublicKey: authorizerPubKey, recipientSecretKey: privKey, nonce: eakN) else {
            throw E3dbError.cryptoError("Failed to decrypt access key")
        }

        return ak
    }
    
    static func decrypt(eak: String, authorizerPubKey: String, clientPrivateKey: String) throws -> RawAccessKey {
        guard let (eak, eakN) = try b64SplitEak(eak) else {
            throw E3dbError.cryptoError("Invalid access key format")
        }

        guard let authorizerPubKey = Box.PublicKey(base64UrlEncoded: authorizerPubKey),
              let privKey = Box.SecretKey(base64UrlEncoded: clientPrivateKey),
              let ak = sodium.box.open(authenticatedCipherText: eak, senderPublicKey: authorizerPubKey, recipientSecretKey: privKey, nonce: eakN) else {
            throw E3dbError.cryptoError("Failed to decrypt access key")
        }

        return ak
    }
}

// MARK: Record Data Crypto

extension Crypto {

    private static func generateDataKey() -> SecretBox.Key {
        return sodium.secretBox.key()
    }

    private static func encrypt(value: Bytes?, key: SecretBox.Key) throws -> SecretBoxCipherNonce {
        guard let data = value,
              let cipher: SecretBoxCipherNonce = sodium.secretBox.seal(message: data, secretKey: key) else {
            throw E3dbError.cryptoError("Failed to encrypt value")
        }
        return cipher
    }

    static func encrypt(recordData: RecordData, ak: RawAccessKey) throws -> CipherData {
        var encrypted = CipherData()

        for (key, value) in recordData.cleartext {
            let bytes       = value.data(using: .utf8)?.bytes
            let dk          = generateDataKey()
            let (ef, efN)   = try encrypt(value: bytes, key: dk)
            let (edk, edkN) = try encrypt(value: dk, key: ak)
            encrypted[key]  = try b64Join(edk, edkN, ef, efN)
        }
        return encrypted
    }

    private static func decrypt(ciphertext: Bytes, nonce: SecretBox.Nonce, key: SecretBox.Key) throws -> Bytes {
        guard let plain = sodium.secretBox.open(authenticatedCipherText: ciphertext, secretKey: key, nonce: nonce) else {
            throw E3dbError.cryptoError("Failed to decrypt value")
        }
        return plain
    }

    public static func decryptAnonymous(ciphertext: Bytes, pubKey: Box.PublicKey, secretKey: Box.SecretKey) throws -> Bytes {
        guard let plain = sodium.box.open(anonymousCipherText: ciphertext, recipientPublicKey: pubKey, recipientSecretKey: secretKey) else {
            throw E3dbError.cryptoError("Failed to decrypt value")
        }
        return plain
    }
    
    static func decrypt(cipherData: CipherData, ak: RawAccessKey) throws -> RecordData {
        var decrypted = Cleartext()

        for (key, value) in cipherData {
            guard let (edk, edkN, ef, efN) = try b64SplitData(value) else {
                throw E3dbError.cryptoError("Invalid data format")
            }
            let dk    = try decrypt(ciphertext: edk, nonce: edkN, key: ak)
            let field = try decrypt(ciphertext: ef, nonce: efN, key: dk)
            decrypted[key] = field.utf8String
        }
        return RecordData(cleartext: decrypted)
    }
    
    
}

// MARK: Document Crypto

extension Crypto {

    static func signature(doc: Signable, signingKey: Sign.SecretKey) -> String? {
        let message = try? Crypto.base64UrlDecoded(string: doc.serialized())
        return sodium.sign.signature(message: message!, secretKey: signingKey)?.base64UrlEncodedString()
    }

    static func verify(doc: Signable, encodedSig: String, verifyingKey: Sign.PublicKey) -> Bool? {
        let message = Bytes(doc.serialized().utf8)
        return Bytes(base64UrlEncoded: encodedSig)
            .map { sodium.sign.verify(message: message, publicKey: verifyingKey, signature: $0) }
    }


}

// MARK: Note Crypto

extension Crypto {
    static func signatureVersion() -> String{
      // UUIDv5 TFSP1;ED25519;BLAKE2B
      return "e7737e7c-1637-511e-8bab-93c4f3e26fd9"
    }
    
    static func signField(key: String, value: String, signingKey: Sign.SecretKey, objectSalt: String? = nil) throws -> String {
        var salt = objectSalt
        if salt == nil {
            salt = UUID().uuidString
        }
        guard let message = try? Crypto.hash(stringToHash: String(format: "%@%@%@", salt!, key, value)) else {
            throw E3dbError.cryptoError("Failed to sign field")
        }
        let messageBytes = Bytes(message.utf8)
        let signature = sodium.sign.signature(message: messageBytes, secretKey: signingKey)?.base64UrlEncodedString()
        let prefix = String(format:"%@;%@;%d;%@", Crypto.signatureVersion(), salt!, signature!.count, signature!)
        return String(format:"%@%@", prefix, value)
    }
    
    static func validateField(key: String, value: String, signingKey: Sign.SecretKey, objectSalt: String? = nil) throws -> String {
        let fields = value.split(separator: ";")
        if (String(fields[0]) != Crypto.signatureVersion()) {
            throw E3dbError.cryptoError("signature version does not match \(fields[0])")
        }
        if objectSalt != nil && String(fields[1]) != objectSalt {
            throw E3dbError.cryptoError("object salt does not match")
        }
        let headerLength = fields[0].count + fields[1].count + fields[2].count + 3
        let signatureLength = Int(fields[2])!
    
        let signatureIndex = String.Index(utf16Offset: headerLength, in: value)
        let plainTextIndex = String.Index(utf16Offset: headerLength + signatureLength, in: value)
        
        let signature = String(value[signatureIndex..<plainTextIndex])
        let plainText = String(value[plainTextIndex...])
        
        guard let signedMessage = try? Crypto.hash(stringToHash: String.init(format: "%@%@%@", String(fields[1]), key, plainText)) else {
            throw E3dbError.cryptoError("Failed to hash verifying field")
        }
        
        let valid = Crypto.verify(doc: signableString(signedMessage), encodedSig: signature, verifyingKey: signingKey)
        if valid != true {
            throw E3dbError.cryptoError("Could not verify field")
        }
        
        return plainText
    }

    static func encryptNote(note: Note, accessKey: RawAccessKey, signingKey: String) throws -> Note {
        var encryptedNote = note
        let signatureSalt = UUID().uuidString
        guard let signingKeyBytes = Box.SecretKey(base64UrlEncoded: signingKey) else { throw E3dbError.cryptoError("Could not decode signing key") }

        let noteSignature = try Crypto.signField(key: "signature", value: signatureSalt, signingKey: signingKeyBytes)
        encryptedNote.signature = noteSignature
        
        var encryptedData:[String: String] = [:]
        for (plain, data) in encryptedNote.data {
            let signedField =  try Crypto.signField(
                key: plain,
                value: data,
                signingKey: signingKeyBytes,
                objectSalt: signatureSalt
            )
            encryptedData[plain] = try Crypto.encryptField(plain: signedField, ak: accessKey)
        }
        encryptedNote.data = encryptedData
        return encryptedNote
    }
    
    static func decryptNote(encryptedNote: Note, privateEncryptionKey: String, publicEncryptionKey: String, publicSigningKey: String) throws -> Note {
        var unencryptedNote = encryptedNote
        guard let signingKeyBytes = Box.SecretKey(base64UrlEncoded: publicSigningKey) else {
            throw E3dbError.cryptoError("Invalid signing key")
        }
        let ak = try Crypto.decrypt(eak: unencryptedNote.noteKeys.encryptedAccessKey, authorizerPubKey: publicEncryptionKey, clientPrivateKey: privateEncryptionKey)
        
        guard let verifiedSalt = try? Crypto.validateField(key: "signature", value: unencryptedNote.signature!, signingKey: signingKeyBytes) else {
            throw E3dbError.cryptoError("Could not verify signature salt")
        }
        var copySalt: String? = verifiedSalt
        if verifiedSalt == unencryptedNote.signature! {
            copySalt = nil
        }
        var encryptedData:[String: String] = [:]
        for (plain, data) in unencryptedNote.data {
            let decryptedData = try Crypto.decryptField(encrypted: data, ak: ak)
            let verifiedData = try Crypto.validateField(key: plain, value: decryptedData, signingKey: signingKeyBytes, objectSalt: copySalt)
            encryptedData[plain] = verifiedData
        }
        unencryptedNote.data = encryptedData
        return unencryptedNote
    }
    
    static func encryptField(plain: String, ak: RawAccessKey) throws -> String {
        let bytes       = plain.data(using: .utf8)?.bytes
        let dk          = generateDataKey()
        let (ef, efN)   = try encrypt(value: bytes, key: dk)
        let (edk, edkN) = try encrypt(value: dk, key: ak)
        let encrypted  = try b64Join(edk, edkN, ef, efN)
        return encrypted
    }
    
    static func decryptField(encrypted: String, ak: RawAccessKey) throws -> String {
        guard let (edk, edkN, ef, efN) = try b64SplitData(encrypted) else {
            throw E3dbError.cryptoError("Invalid data format")
        }
        let dk    = try decrypt(ciphertext: edk, nonce: edkN, key: ak)
        let field = try decrypt(ciphertext: ef, nonce: efN, key: dk)
        guard let plainField = field.utf8String else {
            throw E3dbError.cryptoError("Invalid field encoding")
        }
        return plainField
    }
    
    public static func sign<T: Signable>(document: T, privateSigningKey: String) throws -> SignedDocument<T> {
        guard let privSigKey = Sign.SecretKey(base64UrlEncoded: privateSigningKey),
              let signature  = Crypto.signature(doc: document, signingKey: privSigKey) else {
            throw E3dbError.cryptoError("Failed to sign document")
        }
        return SignedDocument(document: document, signature: signature)
    }
}



// MARK: Files Crypto

struct EncryptedFileInfo {
    let url: URL
    let md5: String
    let size: UInt64
}

extension Crypto {

    private typealias Stream = SecretStream.XChaCha20Poly1305

    // Header: v || '.' || edk || '.' ||  edkN || '.'
    private static func createHeader(dk: Stream.Key, ak: RawAccessKey) throws -> String {
        let (edk, edkN) = try encrypt(value: dk, key: ak)
        let b64Encoded  = try b64Join(edk, edkN)
        return [Crypto.version, b64Encoded]
            .map { $0 + "." }
            .joined()
    }

    static func md5(of file: URL) throws -> String {
        #if !canImport(CommonCrypto)
            throw E3dbError.cryptoError("Cannot perform MD5 without CommonCrypto module.")
        #endif
        let input   = try FileHandle(forReadingFrom: file)
        let context = UnsafeMutablePointer<CC_MD5_CTX>.allocate(capacity: 1)
        defer {
            input.closeFile()
            context.deallocate()
        }
        CC_MD5_Init(context)

        var buffer = input.readData(ofLength: blockSize)
        while !buffer.isEmpty {
            buffer.updateMD5(context: context)
            buffer = input.readData(ofLength: blockSize)
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, context)
        return Data(digest).base64EncodedString()
    }

    // swiftlint:disable function_body_length
    static func encrypt(fileAt src: URL, ak: RawAccessKey) throws -> EncryptedFileInfo {
        #if !canImport(CommonCrypto)
            throw E3dbError.cryptoError("Cannot perform file encryption without CommonCrypto module.")
        #endif

        let dk = sodium.secretStream.xchacha20poly1305.key()
        guard let stream = sodium.secretStream.xchacha20poly1305.initPush(secretKey: dk) else {
            throw E3dbError.cryptoError("Failed to initialize stream")
        }
        guard let dst = FileManager.tempBinFile() else {
            throw E3dbError.cryptoError("Failed to open file")
        }
        let input  = try FileHandle(forReadingFrom: src)
        let output = try FileHandle(forWritingTo: dst)

        // manage resources
        let context = UnsafeMutablePointer<CC_MD5_CTX>.allocate(capacity: 1)
        defer {
            input.closeFile()
            output.closeFile()
            context.deallocate()
        }
        CC_MD5_Init(context)

        // write headers
        let e3dbHeader   = try createHeader(dk: dk, ak: ak)
        let headerData   = Data(e3dbHeader.utf8)
        let streamHeader = Data(_: stream.header())
        output.write(headerData)
        output.write(streamHeader)
        headerData.updateMD5(context: context)
        streamHeader.updateMD5(context: context)

        // simulate 2-element queue for easy EOF detection
        var headBuf = input.readData(ofLength: blockSize)
        var nextBuf = input.readData(ofLength: blockSize)
        var size    = UInt64(headerData.count + streamHeader.count)
        while !headBuf.isEmpty {
            let tag: Stream.Tag = nextBuf.isEmpty ? .FINAL : .MESSAGE
            guard let cipherText = stream.push(message: headBuf.bytes, tag: tag) else {
                throw E3dbError.cryptoError("Failed to encrypted data")
            }
            let cipherData = Data(_: cipherText)
            output.write(cipherData)
            cipherData.updateMD5(context: context)

            size   += UInt64(cipherText.count)
            headBuf = nextBuf
            nextBuf = input.readData(ofLength: blockSize)
        }
        // ensure EOF
        guard headBuf.isEmpty else {
            throw E3dbError.cryptoError("An error occured reading input data")
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, context)
        let md5 = Data(digest).base64EncodedString()
        return EncryptedFileInfo(url: dst, md5: md5, size: size)
    }

    static func decrypt(fileAt src: URL, to dst: URL, ak: RawAccessKey) throws {
        #if !canImport(CommonCrypto)
            throw E3dbError.cryptoError("Cannot perform file decryption without CommonCrypto module.")
        #endif

        let input  = try FileHandle(forReadingFrom: src)
        let output = try FileHandle(forWritingTo: dst)

        // manage resources
        defer {
            input.closeFile()
            output.closeFile()
        }

        // read version
        let delimiter = [UInt8](".".utf8)[0]
        let fileVer   = input.read(until: delimiter)
        guard fileVer.count == 1,
              let ver = String(data: fileVer, encoding: .utf8),
              ver == Crypto.version else {
            throw E3dbError.cryptoError("Unknown files version")
        }

        // read edk, edkN and decrypt to get dk
        let edkBuf  = input.read(until: delimiter)
        let edkNBuf = input.read(until: delimiter)
        guard !edkBuf.isEmpty, !edkNBuf.isEmpty,
              let edkStr  = String(bytes: edkBuf, encoding: .utf8),
              let edkNStr = String(bytes: edkNBuf, encoding: .utf8) else {
            throw E3dbError.cryptoError("Invalid header format")
        }
        let edk  = try base64UrlDecoded(string: edkStr)
        let edkN = try base64UrlDecoded(string: edkNStr)
        let dk   = try decrypt(ciphertext: edk, nonce: edkN, key: ak)

        // read stream header
        let header = input.readData(ofLength: Stream.HeaderBytes).bytes
        guard header.count == Stream.HeaderBytes else {
            throw E3dbError.cryptoError("Invalid header format")
        }

        // read, decrypt, write file
        guard let stream = sodium.secretStream.xchacha20poly1305.initPull(secretKey: dk, header: header) else {
            throw E3dbError.cryptoError("Failed to initialize stream")
        }
        let bufferSize = blockSize + Stream.ABytes
        var cipherText = input.readData(ofLength: bufferSize)
        while !cipherText.isEmpty {
            guard let (plainText, tag) = stream.pull(cipherText: cipherText.bytes),
                  tag == .MESSAGE || tag == .FINAL else {
                throw E3dbError.cryptoError("Failed to decrypt values")
            }
            let plainData = Data(_: plainText)
            output.write(plainData)
            cipherText = input.readData(ofLength: bufferSize)
        }
    }
}

// Mark Identity Functions

extension Crypto {
    static func hash(stringToHash: String, rounds: UInt32 = 10000) throws -> String {
        let hash = sodium.genericHash.hash(message: stringToHash.data(using: .utf8)!.bytes)
        return try Crypto.base64UrlEncoded(bytes: hash!)
    }

    static func sha256(data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(Array(data), UInt32(data.count), &digest)
        // convert the sha256 to a url encoded string
        let hashString = try? Crypto.base64UrlEncoded(bytes: digest)
        return hashString!
    }

    static func deriveNoteCreds(realmName: String, username: String, password: String, type: String = "password") throws -> NoteCredentials {
        var username = username.lowercased()
        var nameSeed = String(format: "%@@realm:%@", username, realmName)
        switch (type) {
        case "email_otp":
            nameSeed = String(format: "broker:%@", nameSeed)
            break
        case "tozny_otp":
            nameSeed = String(format: "tozny_otp:%@", nameSeed)
            break
        case "password":
            break
        default:
            throw E3dbError.configError("Note cred type: \(type) is not supported")
        }
        let noteName = try Crypto.hash(stringToHash: nameSeed)
        let cryptoKeyPair = try Crypto.deriveCryptoKeys(password: password, salt: nameSeed)
        let signingKeyPair = try Crypto.deriveSigningKeys(password: password, salt: cryptoKeyPair.publicKey + cryptoKeyPair.privateKey)
        return NoteCredentials(name: noteName, encryptionKeyPair: cryptoKeyPair, signingKeyPair: signingKeyPair)
    }

    static func deriveSigningKeys(password: String, salt: String, rounds: UInt32 = 10000) throws -> SigningKeyPair {
        let seed = try Crypto.derivePassword(secret: password, salt: salt, rounds: rounds)
        let baseSeed = try Crypto.base64UrlDecoded(string: seed)

        guard let rawSigningKeys = sodium.sign.keyPair(seed: baseSeed) else {
            throw E3dbError.cryptoError("Unable to seed signing keypair")
        }

        let pubSignKey = try Crypto.base64UrlEncoded(bytes: rawSigningKeys.publicKey)
        let privSignKey = try Crypto.base64UrlEncoded(bytes: rawSigningKeys.secretKey)

        return SigningKeyPair(privateKey: privSignKey, publicKey: pubSignKey)
    }

    static func deriveCryptoKeys(password: String, salt: String, rounds: UInt32 = 10000) throws -> EncryptionKeyPair {
        let seed = try Crypto.derivePassword(secret: password, salt: salt, rounds: rounds)
        let baseSeed = try Crypto.base64UrlDecoded(string: seed)

        guard let rawCryptoKeys = sodium.box.keyPair(seed: baseSeed) else {
            throw E3dbError.cryptoError("Unable to seed encryption keypair")
        }
        let pubKey = try Crypto.base64UrlEncoded(bytes: rawCryptoKeys.publicKey)
        let privKey = try Crypto.base64UrlEncoded(bytes: rawCryptoKeys.secretKey)

        return EncryptionKeyPair(privateKey: privKey, publicKey: pubKey)
    }

    static func derivePassword(secret: String, salt: String, rounds: UInt32) throws -> String {
        var saltBytes: [UInt8] = Array(salt.utf8)
        guard let pbk = try? Crypto.pbkdf2(hash: CCPBKDFAlgorithm(kCCPRFHmacAlgSHA512), password: secret, salt: saltBytes, keyCount: 32, rounds: rounds) else {
            throw E3dbError.cryptoError("Failed to generate key seed")
        }
        guard let pbkString = try? Crypto.base64UrlEncoded(bytes: pbk.bytes) else {
            throw E3dbError.cryptoError("Failed to b64 encode derived key seed")
        }
        return pbkString
    }

    static func pbkdf2(hash: CCPBKDFAlgorithm, password: String, salt: [UInt8], keyCount: Int, rounds: UInt32) throws -> Data {
        var localDerivedKeyData:Data = Data(count: keyCount)
        let status = try localDerivedKeyData.withUnsafeMutableBytes() {
            (outputBytes: UnsafeMutablePointer<UInt8>) -> Void in
            let passwordData = password.data(using: String.Encoding.utf8, allowLossyConversion: false)!
            let passwordBuffer = try passwordData.withUnsafeBytes {
                (passBytes: UnsafePointer<Int8>) -> Void in
                let derivationStatus = CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes,
                        passwordData.count,
                        UnsafePointer<UInt8>(salt),
                        salt.count,
                        CCPseudoRandomAlgorithm(hash),
                        rounds,
                        outputBytes,
                        keyCount)
                if (derivationStatus != 0) {
                    throw E3dbError.cryptoError("Failed to derive key seed from password with pbkdf2")
                }
            }
        }
        return localDerivedKeyData
    }
}

