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
}
