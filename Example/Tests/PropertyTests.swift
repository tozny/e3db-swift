import XCTest
import SwiftCheck
@testable import E3db

extension Data: Arbitrary {
    public static var arbitrary: Gen<Data> {
        return [UInt8].arbitrary.flatMap { bytes in
            return Gen<Data>.pure(Data(bytes: bytes))
        }
    }
}

extension UUID: Arbitrary {
    public static var arbitrary: Gen<UUID> {
        return Gen<UUID>.pure(UUID())
    }
}

extension URL: Arbitrary {
    public static var arbitrary: Gen<URL> {
        return Gen<URL>.compose { c in
            return URL(fileURLWithPath: c.generate())
        }
    }
}

extension FileMeta: Arbitrary {
    public static var arbitrary: Gen<FileMeta> {
        return Gen<FileMeta>.compose { c in
            FileMeta(
                fileUrl: c.generate(),
                fileName: c.generate(),
                checksum: c.generate(),
                compression: c.generate(),
                size: c.generate()
            )
        }
    }
}

extension ClientMeta: Arbitrary {
    public static var arbitrary: Gen<ClientMeta> {
        return Gen<ClientMeta>.compose { c in
            ClientMeta(
                writerId: c.generate(),
                userId: c.generate(),
                type: c.generate(),
                plain: c.generate(),
                fileMeta: c.generate()
            )
        }
    }
}

extension EncryptedDocument: Arbitrary {
    public static var arbitrary: Gen<EncryptedDocument> {
        return Gen<EncryptedDocument>.compose { c in
            EncryptedDocument(
                clientMeta: c.generate(),
                encryptedData: c.generate(),
                recordSignature: c.generate()
            )
        }
    }
}

struct Base64UrlEncodedString: Arbitrary {
    let value: String

    static var arbitrary: Gen<Base64UrlEncodedString> {
        return Data.arbitrary.flatMap { data in
            let manual = data.base64URLEncodedString()
            return Gen<Base64UrlEncodedString>.pure(Base64UrlEncodedString(value: manual))
        }
    }
}

class PropertyTests: XCTestCase, TestUtils {
    static let testClient = createClientSync()
    
    func testBase64urlEncoding() {
        property("Base64url encoding for sodium should match manual") <- forAll { (data: Data) in
            let sodiumEncoded = try? Crypto.base64UrlEncoded(data: data)
            let manualEncoded = data.base64URLEncodedString()
            return sodiumEncoded != nil && sodiumEncoded! == manualEncoded
        }
    }

    func testBase64urlDecoding() {
        property("Base64url decoding for sodium should match manual") <- forAll { (encoded: Base64UrlEncodedString) in
            let sodiumDecoded = try? Crypto.base64UrlDecoded(string: encoded.value)
            let manualDecoded = Data(base64URLEncoded: encoded.value)
            return sodiumDecoded != nil && manualDecoded != nil && sodiumDecoded! == manualDecoded!
        }
    }

    func testEncodeSignVerify() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        property("Signatures should verify after encoding and decoding") <- forAll { (encrypted: EncryptedDocument) in
            let signed  = try! PropertyTests.testClient.sign(document: encrypted)
            let encoded = try! encoder.encode(signed)
            let decoded = try! decoder.decode(SignedDocument<EncryptedDocument>.self, from: encoded)
            return try! PropertyTests.testClient.verify(signed: decoded, pubSigKey: PropertyTests.testClient.config.publicSigKey)
        }
    }
}
