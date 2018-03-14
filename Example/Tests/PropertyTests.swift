import XCTest
import Sodium
import SwiftCheck

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
        return [UInt8].arbitrary.flatMap { bytes in
            let encoded = Data(bytes: bytes)
            let manual  = encoded.base64URLEncodedString()
            return Gen<Base64UrlEncodedString>.pure(Base64UrlEncodedString(value: manual))
        }
    }
}

class PropertyTests: XCTestCase, TestUtils {
    private let sodium = Sodium()

    func testBase64urlEncoding() {
        property("Base64url encoding for sodium should match manual") <- forAll { (data: Data) in
            let sodiumEncoded = self.sodium.utils.bin2base64(data, variant: .URLSAFE_NO_PADDING)
            let manualEncoded = data.base64URLEncodedString()
            return sodiumEncoded != nil && sodiumEncoded! == manualEncoded
        }
    }

    func testBase64urlDecoding() {
        property("Base64url decoding for sodium should match manual") <- forAll { (encoded: Base64UrlEncodedString) in
            let sodiumDecoded = self.sodium.utils.base642bin(encoded.value, variant: .URLSAFE_NO_PADDING)
            let manualDecoded = Data(base64URLEncoded: encoded.value)
            return sodiumDecoded != nil && manualDecoded != nil && sodiumDecoded! == manualDecoded!
        }
    }
}
