import ResponseDetective
import UIKit
import XCTest
@testable import E3db

import let ToznySwish.immediateScheduler

// non-sensitive test data
// for running integration tests
struct TestData {
    static let apiUrl = ""
    static let token  = ""

    // Let's Encrypt: https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem.txt
    // Intermediate certificate, converted to DER and encoded to base64
    static let validCert = """
MIIEkjCCA3qgAwIBAgIQCgFBQgAAAVOFc2oLheynCDANBgkqhkiG9w0BAQsFADA/MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMTDkRTVCBSb290IENBIFgzMB4XDTE2MDMxNzE2NDA0NloXDTIxMDMxNzE2NDA0NlowSjELMAkGA1UEBhMCVVMxFjAUBgNVBAoTDUxldCdzIEVuY3J5cHQxIzAhBgNVBAMTGkxldCdzIEVuY3J5cHQgQXV0aG9yaXR5IFgzMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnNMM8FrlLke3cl03g7NoYzDq1zUmGSXhvb418XCSL7e4S0EFq6meNQhY7LEqxGiHC6PjdeTm86dicbp5gWAf15Gan/PQeGdxyGkOlZHP/uaZ6WA8SMx+yk13EiSdRxta67nsHjcAHJyse6cF6s5K671B5TaYucv9bTyWaN8jKkKQDIZ0Z8h/pZq4UmEUEz9l6YKHy9v6Dlb2honzhT+Xhq+w3Brvaw2VFn3EK6BlspkENnWAa6xK8xuQSXgvopZPKiAlKQTGdMDQMc2PMTiVFrqoM7hD8bEfwzB/onkxEz0tNvjj/PIzark5McWvxI0NHWQWM6r6hCm21AvA2H3DkwIDAQABo4IBfTCCAXkwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwfwYIKwYBBQUHAQEEczBxMDIGCCsGAQUFBzABhiZodHRwOi8vaXNyZy50cnVzdGlkLm9jc3AuaWRlbnRydXN0LmNvbTA7BggrBgEFBQcwAoYvaHR0cDovL2FwcHMuaWRlbnRydXN0LmNvbS9yb290cy9kc3Ryb290Y2F4My5wN2MwHwYDVR0jBBgwFoAUxKexpHsscfrb4UuQdf/EFWCFiRAwVAYDVR0gBE0wSzAIBgZngQwBAgEwPwYLKwYBBAGC3xMBAQEwMDAuBggrBgEFBQcCARYiaHR0cDovL2Nwcy5yb290LXgxLmxldHNlbmNyeXB0Lm9yZzA8BgNVHR8ENTAzMDGgL6AthitodHRwOi8vY3JsLmlkZW50cnVzdC5jb20vRFNUUk9PVENBWDNDUkwuY3JsMB0GA1UdDgQWBBSoSmpjBH3duubRObemRWXv86jsoTANBgkqhkiG9w0BAQsFAAOCAQEA3TPXEfNjWDjdGBX7CVW+dla5cEilaUcne8IkCJLxWh9KEik3JHRRHGJouM2VcGfl96S8TihRzZvoroed6ti6WqEBmtzw3Wodatg+VyOeph4EYpr/1wXKtx8/wApIvJSwtmVi4MFU5aMqrSDE6ea73Mj2tcMyo5jMd6jmeWUHK8so/joWUoHOUgwuX4Po1QYz+3dszkDqMp4fklxBwXRsW10KXzPMTZ+sOPAveyxindmjkW8lGy+QsRlGPfZ+G6Z6h7mjem0Y+iWlkYcV4PIWL1iwBi8saCbGS5jN2p8M+X+Q7UNKEkROb3N6KOqkqm57TH2H3eDJAkSnh6/DNFu0Qg==
"""
    // Go Daddy: https://certs.godaddy.com/repository/gd-class2-root.crt
    // Intermediate certificate, converted to DER and encoded to base64
    static let invalidCert = """
MIIEADCCAuigAwIBAgIBADANBgkqhkiG9w0BAQUFADBjMQswCQYDVQQGEwJVUzEhMB8GA1UEChMYVGhlIEdvIERhZGR5IEdyb3VwLCBJbmMuMTEwLwYDVQQLEyhHbyBEYWRkeSBDbGFzcyAyIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTA0MDYyOTE3MDYyMFoXDTM0MDYyOTE3MDYyMFowYzELMAkGA1UEBhMCVVMxITAfBgNVBAoTGFRoZSBHbyBEYWRkeSBHcm91cCwgSW5jLjExMC8GA1UECxMoR28gRGFkZHkgQ2xhc3MgMiBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTCCASAwDQYJKoZIhvcNAQEBBQADggENADCCAQgCggEBAN6d1+pXGEmhW+vXX0iG6r7d/+TvZxz0ZWizV3GgXne77ZtJ6XCAPVYYYwhv2vLM0D9/AlQiVBDYsoHUwHU9S3/Hd8M+eKsaA7Ugay9qK7HFiH7Eux6wwdhFJ2+qN1j3hybX2C32qRe3H3I2TqYXP2WYktsqbl2i/ojgC95/5Y0V4evLOtXiEqITLdiOr18SPaAIBQi2XKVlOARFmR6jYGB0xUGlcmIbYsUfb18aQr4CUWWoriMYavx4A6lNf4DD+qta/KFApMoZFv6yyO9ecw3ud72a9nmYvLEHZ6IVDd2gWMZEewo+YihfukEHU1jPEX44dMX4/7VpkI+EdOqXG68CAQOjgcAwgb0wHQYDVR0OBBYEFNLEsNKR1EwRcbNhyz2h/t2oatTjMIGNBgNVHSMEgYUwgYKAFNLEsNKR1EwRcbNhyz2h/t2oatTjoWekZTBjMQswCQYDVQQGEwJVUzEhMB8GA1UEChMYVGhlIEdvIERhZGR5IEdyb3VwLCBJbmMuMTEwLwYDVQQLEyhHbyBEYWRkeSBDbGFzcyAyIENlcnRpZmljYXRpb24gQXV0aG9yaXR5ggEAMAwGA1UdEwQFMAMBAf8wDQYJKoZIhvcNAQEFBQADggEBADJL87LKPpH8EsahB4yOd6AzBhRckB4Y9wimPQoZ+YeAEW5p5JYXMP80kWNyOO7MHAGjHZQopDH2esRU1/blMVgDoszOYtuURXO1v0XJJLXVggKtI3lpjbi2Tc7PTMozI+gciKqdi0FuFskg5YmezTvacPd+mSYgFFQlq25zheabIZ0KbIIOqPjCDPoQHmyW74cNxA9hi63ugyuV+I6ShHI56yDqg+2DzZduCLzrTia2cyvk0/ZM/iZx4mERdEr/VxqHD3VILs9RaRegAhJhldXRQLIQTO7ErBBDpqWeCtWVYpoNz4iCxTIM5CufReYNnyicsbkqWletNw+vHX/bvZ8=
"""
}

protocol TestUtils {
    func asyncTest(_ testName: String, test: @escaping (XCTestExpectation) -> Void)
    func clientWithConfig() -> (Client, Config)
    func clientWithId() -> (Client, UUID)
    func client() -> Client
    func writeTestRecord(_ e3db: Client, _ contentType: String) -> Record
    func deleteRecord(_ record: Record, e3db: Client)
    func deleteAllRecords(_ e3db: Client)
    func serializeBlns() -> [[String: String]]
    func loadBlnsSerializationResults(filename: String) -> [[String: String]]
    func writeBlnsTestsToFile(tests: [[String: String]])
    static func verboseUrlSession() -> URLSession
    static func createClientSync() -> Client
    static func createKeySync(client: Client, recordType: String) -> EAKInfo
}

extension TestUtils where Self: XCTestCase {

    func asyncTest(_ testName: String, test: @escaping (XCTestExpectation) -> Void) {
        test(expectation(description: testName))
        waitForExpectations(timeout: 10, handler: { XCTAssertNil($0) })
    }

    func clientWithConfig() -> (Client, Config) {
        var e3db: Client?
        var conf: Config?
        let newClient = #function + UUID().uuidString
        asyncTest(newClient) { (expect) in
            let session = Self.verboseUrlSession()
            Client.register(token: TestData.token, clientName: newClient, urlSession: session, apiUrl: TestData.apiUrl) { (result) in
                XCTAssertNotNil(result.value)
                conf = result.value
                e3db = Client(config: conf!, urlSession: session)
                expect.fulfill()
            }
        }
        return (e3db!, conf!)
    }

    func clientWithId() -> (Client, UUID) {
        let (e3db, conf) = clientWithConfig()
        return (e3db, conf.clientId)
    }

    func client() -> Client {
        let (e3db, _) = clientWithConfig()
        return e3db
    }

    func writeTestRecord(_ e3db: Client, _ contentType: String = "test-data") -> Record {
        var record: Record?
        asyncTest(#function + "write") { (expect) in
            e3db.write(type: contentType, data: RecordData(cleartext: ["test": "message"])) { (result) in
                record = result.value!
                expect.fulfill()
            }
        }
        return record!
    }

    func deleteRecord(_ record: Record, e3db: Client) {
        asyncTest(#function + "delete") { (expect) in
            e3db.delete(recordId: record.meta.recordId, version: record.meta.version) { _ in expect.fulfill() }
        }
    }

    func deleteAllRecords(_ e3db: Client) {
        let test = #function + "delete all"
        var records = [Record]()
        asyncTest(test) { (expect) in
            e3db.query(params: QueryParams()) { (result) in
                records = result.value!.records
                expect.fulfill()
            }
        }
        records.forEach { (record) in
            deleteRecord(record, e3db: e3db)
        }
    }

    func serializeBlns() -> [[String: String]] {
        guard let jsonUrl = Bundle(for: type(of: self)).url(forResource: "blns", withExtension: "json") else {
            XCTFail("Could not load blns.json")
            return []
        }

        do {
            let jsonData = try Data(contentsOf: jsonUrl)
            let strings  = try JSONDecoder().decode([String].self, from: jsonData)

            let tests = strings.enumerated().map { pair -> [String : String] in
                let elementIdx = "\(pair.offset)"
                let recordData = RecordData(cleartext: [elementIdx: pair.element])
                let serialized = recordData.serialized()
                let b64Encoded = Data(serialized.utf8).base64EncodedString()
                return [
                    "index": elementIdx,
                    "element": pair.element,
                    "serialized": serialized,
                    "b64Encoded": b64Encoded
                ]
            }
            return tests
        } catch {
            XCTFail(error.localizedDescription)
        }
        return []
    }

    func loadBlnsSerializationResults(filename: String) -> [[String: String]] {
        guard let jsonUrl = Bundle(for: type(of: self)).url(forResource: filename, withExtension: "json") else {
            XCTFail("Could not load \(filename).json")
            return []
        }

        do {
            let data = try Data(contentsOf: jsonUrl)
            return try JSONDecoder().decode([[String: String]].self, from: data)
        } catch {
            XCTFail(error.localizedDescription)
        }
        return []
    }

    func writeBlnsTestsToFile(tests: [[String: String]]) {
        guard let outputUrl = Bundle(for: type(of: self)).url(forResource: "blns-swift", withExtension: "json") else {
            return XCTFail("Could not load blns-swift.json")
        }

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        do {
            let encodedTests = try jsonEncoder.encode(tests)
            try encodedTests.write(to: outputUrl)
            print("BLNS tests serialized to \(outputUrl.absoluteString)")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    static func verboseUrlSession() -> URLSession {
        let verboseConfig = URLSession.shared.configuration
        ResponseDetective.enable(inConfiguration: verboseConfig)
        return URLSession(configuration: verboseConfig)
    }

    static func createClientSync() -> Client {
        var e3db: Client?
        let newClient = #function + UUID().uuidString
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .background).async {
            let session = verboseUrlSession()
            Client.register(token: TestData.token, clientName: newClient, urlSession: session, apiUrl: TestData.apiUrl, scheduler: immediateScheduler) { (result) in
                XCTAssertNotNil(result.value)
                e3db = Client(config: result.value!, urlSession: session, scheduler: immediateScheduler)
                group.leave()
            }
        }
        guard group.wait(timeout: .now() + 20) == .success else {
            fatalError("Timed out")
        }
        return e3db!
    }

    static func createKeySync(client: Client, recordType: String) -> EAKInfo {
        var eakInfo: EAKInfo?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .background).async {
            client.createWriterKey(type: recordType) { result in
                guard case .success(let eak) = result else {
                    return XCTFail("Failed to get eak")
                }
                eakInfo = eak
                group.leave()
            }
        }
        guard group.wait(timeout: .now() + 20) == .success else {
            fatalError("Timed out")
        }
        return eakInfo!
    }
}

// Utility for validating pinned certificates
protocol PinnedCertificate: AnyObject {}
extension PinnedCertificate where Self: URLSessionDelegate {
    typealias CertificateCompletion = (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    func validateCertificate(_ certificate: String, for session: URLSession, challenge: URLAuthenticationChallenge, completion: @escaping CertificateCompletion) {
        // Adapted from OWASP https://www.owasp.org/index.php/Certificate_and_Public_Key_Pinning#iOS
        let cancel = URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge
        let ptr =  UnsafeMutablePointer<SecTrustResultType>.allocate(capacity: 32)

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluate(trust, ptr) == errSecSuccess,
              let serverCert = SecTrustGetCertificateAtIndex(trust, 1) else { // checks intermediate cert (index 1)
                return completion(cancel, nil)
        }

        let serverCertData = SecCertificateCopyData(serverCert) as Data

        guard let pinnedCertData = Data(base64Encoded: certificate),
              pinnedCertData == serverCertData else {
                return completion(cancel, nil)
        }

        // pinning succeeded
        completion(.useCredential, URLCredential(trust: trust))
    }
}

// allows quick comparisons for testing
extension EAKInfo: Equatable {
    public static func ==(lhs: EAKInfo, rhs: EAKInfo) -> Bool {
        return lhs.eak == rhs.eak
    }
}

// MARK: - Collect the memory sizes from different types

protocol MemoryReportable {
    var byteCount: Int { get }
}

extension String: MemoryReportable {
    var byteCount: Int {
        return [UInt8](self.utf8).count
    }
}

extension UUID: MemoryReportable {
    var byteCount: Int {
        return MemoryLayout.size(ofValue: self)
    }
}

extension Dictionary where Key == String, Value == String {
    var byteCount: Int {
        return self.reduce(0) { $0 + $1.key.byteCount + $1.value.byteCount }
    }
}

extension RecordData: MemoryReportable {
    var byteCount: Int {
        return cleartext.byteCount
    }
}

extension ClientMeta: MemoryReportable {
    var byteCount: Int {
        return writerId.byteCount + userId.byteCount + type.byteCount + (plain?.byteCount ?? 0)
    }
}

extension EncryptedDocument: MemoryReportable {
    var byteCount: Int {
        return clientMeta.byteCount + encryptedData.byteCount + recordSignature.byteCount
    }
}

extension SignedDocument: MemoryReportable {
    var byteCount: Int {
        return document.serialized().byteCount + signature.byteCount
    }
}

extension Array where Element == UInt8 {
    func asciiMasked() -> [UInt8] {
        return map { $0 & 127 }
    }
}
