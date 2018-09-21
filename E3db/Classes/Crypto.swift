//
//  Crypto.swift
//  E3db
//

import Foundation
import Sodium

typealias RawAccessKey       = SecretBox.Key
typealias EncryptedAccessKey = String

struct Crypto {
    typealias SecretBoxCipherNonce   = (authenticatedCipherText: Data, nonce: SecretBox.Nonce)
    typealias BoxCipherNonce         = (authenticatedCipherText: Data, nonce: Box.Nonce)
    fileprivate static let sodium    = Sodium()
    fileprivate static let version   = "3"
    fileprivate static let blockSize = 65_536
}

// MARK: Base64url Encoding / Decoding

extension Crypto {
    static func base64UrlEncoded(data: Data) throws -> String {
        guard let encoded = sodium.utils.bin2base64(data, variant: .URLSAFE_NO_PADDING) else {
            throw E3dbError.cryptoError("Failed to encode data")
        }
        return encoded
    }

    static func base64UrlDecoded(string: String) throws -> Data {
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

    static func generateSigningKeyPair() -> Sign.KeyPair? {
        return sodium.sign.keyPair()
    }

    static func generateAccessKey() -> RawAccessKey? {
        return sodium.secretBox.key()
    }

    static func b64Join(_ ciphertexts: Data...) throws -> String {
        return try ciphertexts.map(base64UrlEncoded).joined(separator: ".")
    }

    static func b64SplitData(_ value: String) throws -> (Data, Data, Data, Data)? {
        let split = try b64Split(value)
        guard split.count == 4 else { return nil }
        return (split[0], split[1], split[2], split[3])
    }

    static func b64SplitEak(_ value: String) throws -> (Data, Data)? {
        let split = try b64Split(value)
        guard split.count == 2 else { return nil }
        return (split[0], split[1])
    }

    private static func b64Split(_ value: String) throws -> [Data] {
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
}

// MARK: Record Data Crypto

extension Crypto {

    private static func generateDataKey() throws -> SecretBox.Key {
        guard let secretKey = sodium.secretBox.key() else {
            throw E3dbError.cryptoError("Failed to generate data key")
        }
        return secretKey
    }

    private static func encrypt(value: Data?, key: SecretBox.Key) throws -> SecretBoxCipherNonce {
        guard let data = value,
              let cipher: SecretBoxCipherNonce = sodium.secretBox.seal(message: data, secretKey: key) else {
            throw E3dbError.cryptoError("Failed to encrypt value")
        }
        return cipher
    }

    static func encrypt(recordData: RecordData, ak: RawAccessKey) throws -> CipherData {
        var encrypted = CipherData()

        for (key, value) in recordData.cleartext {
            let bytes       = value.data(using: .utf8)
            let dk          = try generateDataKey()
            let (ef, efN)   = try encrypt(value: bytes, key: dk)
            let (edk, edkN) = try encrypt(value: dk, key: ak)
            encrypted[key]  = try b64Join(edk, edkN, ef, efN)
        }
        return encrypted
    }

    private static func decrypt(ciphertext: Data, nonce: SecretBox.Nonce, key: SecretBox.Key) throws -> Data {
        guard let plain = sodium.secretBox.open(authenticatedCipherText: ciphertext, secretKey: key, nonce: nonce) else {
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
            decrypted[key] = String(data: field, encoding: .utf8)
        }
        return RecordData(cleartext: decrypted)
    }
}

// MARK: Document Crypto

extension Crypto {

    static func signature(doc: Signable, signingKey: Sign.SecretKey) -> String? {
        let message = Data(doc.serialized().utf8)
        return sodium.sign.signature(message: message, secretKey: signingKey)?.base64UrlEncodedString()
    }

    static func verify(doc: Signable, encodedSig: String, verifyingKey: Sign.PublicKey) -> Bool? {
        let message = Data(doc.serialized().utf8)
        return Data(base64UrlEncoded: encodedSig)
            .map { sodium.sign.verify(message: message, publicKey: verifyingKey, signature: $0) }
    }

}

// MARK: Files Crypto

extension Crypto {

    private typealias Stream = SecretStream.XChaCha20Poly1305

    private static func initializeStreams(src: URL, dst: URL) throws -> (InputStream, OutputStream) {
        guard let inputStream = InputStream(url: src),
              let outputStream = OutputStream(url: dst, append: false) else {
            throw E3dbError.cryptoError("Failed to open files")
        }
        return (inputStream, outputStream)
    }

    // Header: v || '.' || edk || '.' ||  edkN || '.'
    private static func createHeader(dk: Stream.Key, ak: RawAccessKey) throws -> String {
        let (edk, edkN) = try encrypt(value: dk, key: ak)
        let b64Encoded  = try b64Join(edk, edkN)
        return [Crypto.version, b64Encoded]
            .map { $0 + "." }
            .joined()
    }

    static func encrypt(fileAt src: URL, ak: RawAccessKey) throws -> URL {
        guard let dk = sodium.secretStream.xchacha20poly1305.key(),
              let stream = sodium.secretStream.xchacha20poly1305.initPush(secretKey: dk) else {
            throw E3dbError.cryptoError("Failed to initialize stream")
        }
        let dst = FileManager.tempBinFile()
        let (input, output) = try initializeStreams(src: src, dst: dst)

        // manage resources
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        // write headers
        let e3dbHeader   = try createHeader(dk: dk, ak: ak)
        let headerData   = Data(e3dbHeader.utf8)
        let streamHeader = stream.header()
        guard output.hasSpaceAvailable, output.write(data: headerData) == headerData.count,
              output.hasSpaceAvailable, output.write(data: streamHeader) == streamHeader.count else {
            throw E3dbError.cryptoError("Failed to write ciphertext header")
        }

        // simulate 2-element queue for easy EOF detection
        var headBuf = Data(count: Crypto.blockSize)
        var nextBuf = Data(count: Crypto.blockSize)
        var headAmt = input.read(data: &headBuf)
        var nextAmt = input.read(data: &nextBuf)
        while headAmt > 0 {
            guard nextAmt != -1 else {
                throw E3dbError.cryptoError("An error occured reading input data")
            }
            let tag: Stream.Tag = nextAmt == 0 ? .FINAL : .MESSAGE
            let cipherText = stream.push(message: headBuf, tag: tag)
            guard let data = cipherText, output.write(data: data) != -1 else {
                throw E3dbError.cryptoError("Failed to write encrypted data")
            }

            headAmt = nextAmt
            headBuf = nextBuf
            nextAmt = input.read(data: &nextBuf)
        }
        // ensure EOF
        guard headAmt == 0 else {
            throw E3dbError.cryptoError("An error occured reading input data")
        }
        return dst
    }

    static func decrypt(fileAt src: URL, to dst: URL, ak: RawAccessKey) throws {
        let (input, output) = try initializeStreams(src: src, dst: dst)

        // manage resources
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        // read version
        let delimiter = [UInt8](".".utf8)[0]
        var fileVer   = Data(count: 1)
        guard input.read(until: delimiter, data: &fileVer) != -1,
              let ver = String(data: fileVer, encoding: .utf8),
              ver == Crypto.version else {
            throw E3dbError.cryptoError("Unknown files version")
        }

        // read edk, edkN and decrypt to get dk
        var edkBuf  = Data(count: 100)
        var edkNBuf = Data(count: 100)
        guard input.read(until: delimiter, data: &edkBuf) != -1,
              input.read(until: delimiter, data: &edkNBuf) != -1,
              let edkStr  = String(bytes: edkBuf, encoding: .utf8),
              let edkNStr = String(bytes: edkNBuf, encoding: .utf8) else {
            throw E3dbError.cryptoError("Invalid header format")
        }
        let edk  = try base64UrlDecoded(string: edkStr)
        let edkN = try base64UrlDecoded(string: edkNStr)
        let dk   = try decrypt(ciphertext: edk, nonce: edkN, key: ak)

        // read stream header
        var header = Data(count: Stream.HeaderBytes)
        guard input.read(data: &header) != -1 else {
            throw E3dbError.cryptoError("Invalid header format")
        }

        // read, decrypt, write file
        guard let stream = sodium.secretStream.xchacha20poly1305.initPull(secretKey: dk, header: header) else {
            throw E3dbError.cryptoError("Failed to initialize stream")
        }
        var cipherText = Data(count: Crypto.blockSize + Stream.ABytes)
        var response   = input.read(data: &cipherText)
        while response > 0 {
            guard response != -1 else {
                throw E3dbError.cryptoError("An error occured reading input data")
            }
            guard let (plainText, tag) = stream.pull(cipherText: cipherText),
                  tag == .MESSAGE || tag == .FINAL else {
                throw E3dbError.cryptoError("Failed to decrypt values")
            }
            guard output.write(data: plainText) != -1 else {
                throw E3dbError.cryptoError("An error occured writing output data")
            }
            response = input.read(data: &cipherText)
        }
    }
}
