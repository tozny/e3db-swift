import XCTest
import Sodium
@testable import E3db

class BenchmarkTests: XCTestCase, TestUtils {

    static var data1B: RecordData!
    static var data500B: RecordData!
    static var data250KB: RecordData!
    static var data500KB: RecordData!
    static var data1MB: RecordData!
    static var data2MB: RecordData!
    static var data8MB: RecordData!
    static var data16MB: RecordData!

    static var rec1B: EncryptedDocument!
    static var rec500B: EncryptedDocument!
    static var rec250KB: EncryptedDocument!
    static var rec500KB: EncryptedDocument!
    static var rec1MB: EncryptedDocument!
    static var rec2MB: EncryptedDocument!
    static var rec8MB: EncryptedDocument!
    static var rec16MB: EncryptedDocument!

    static var signed1B: SignedDocument<RecordData>!
    static var signed500B: SignedDocument<RecordData>!
    static var signed250KB: SignedDocument<RecordData>!
    static var signed500KB: SignedDocument<RecordData>!
    static var signed1MB: SignedDocument<RecordData>!
    static var signed2MB: SignedDocument<RecordData>!
    static var signed8MB: SignedDocument<RecordData>!
    static var signed16MB: SignedDocument<RecordData>!

    static var testClient: Client!
    static var testEak: EAKInfo!

    static let recordType = UUID().uuidString
    static let sodium = Sodium()

    override class func setUp() {
        super.setUp()
        testClient = createClientSync()
        testEak    = createKeySync(client: testClient, recordType: recordType)

        data1B    = randomRecordData(numBytes: 1)
        data500B  = randomRecordData(numBytes: 500)
        data250KB = randomRecordData(numBytes: 250_000)
        data500KB = randomRecordData(numBytes: 500_000)
        data1MB   = randomRecordData(numBytes: 1_000_000)
        data2MB   = randomRecordData(numBytes: 2_000_000)
        data8MB   = randomRecordData(numBytes: 8_000_000)
        data16MB  = randomRecordData(numBytes: 16_000_000)

        rec1B    = try! testClient.encrypt(type: recordType, data: data1B, eakInfo: testEak)
        rec500B  = try! testClient.encrypt(type: recordType, data: data500B, eakInfo: testEak)
        rec250KB = try! testClient.encrypt(type: recordType, data: data250KB, eakInfo: testEak)
        rec500KB = try! testClient.encrypt(type: recordType, data: data500KB, eakInfo: testEak)
        rec1MB   = try! testClient.encrypt(type: recordType, data: data1MB, eakInfo: testEak)
        rec2MB   = try! testClient.encrypt(type: recordType, data: data2MB, eakInfo: testEak)
        rec8MB   = try! testClient.encrypt(type: recordType, data: data8MB, eakInfo: testEak)
        rec16MB  = try! testClient.encrypt(type: recordType, data: data16MB, eakInfo: testEak)

        signed1B    = try! testClient.sign(document: data1B)
        signed500B  = try! testClient.sign(document: data500B)
        signed250KB = try! testClient.sign(document: data250KB)
        signed500KB = try! testClient.sign(document: data500KB)
        signed1MB   = try! testClient.sign(document: data1MB)
        signed2MB   = try! testClient.sign(document: data2MB)
        signed8MB   = try! testClient.sign(document: data8MB)
        signed16MB  = try! testClient.sign(document: data16MB)

        printSizes()
    }

    // Generate record data from ascii values to ensure
    // 1-byte-per-character sizes for easier measurement
    static func randomRecordData(numBytes: Int) -> RecordData {
        let data = sodium.randomBytes.buf(length: numBytes)
            .map { $0.asciiMasked() }
            .flatMap { String(data: $0, encoding: .ascii) }
            .map { RecordData(cleartext: ["": $0]) }
        return data!
    }

    static func printSizes() {
        let dats = [data1B, data500B, data250KB, data500KB, data1MB, data2MB, data8MB, data16MB]
        let recs = [rec1B, rec500B, rec250KB, rec500KB, rec1MB, rec2MB, rec8MB, rec16MB]
        let sigs = [signed1B, signed500B, signed250KB, signed500KB, signed1MB, signed2MB, signed8MB, signed16MB]
        for case let (data?, (encrypted?, signed?)) in zip(dats, zip(recs, sigs)) {
            print(String(format: "Data: %8d; Encrypted: %8d; Signed: %8d;", data.byteCount, encrypted.byteCount, signed.byteCount))
        }
    }

    private func encryptionTest(_ recordData: RecordData) {
        _ = try! BenchmarkTests.testClient.encrypt(type: BenchmarkTests.recordType, data: recordData, eakInfo: BenchmarkTests.testEak)
    }

    private func decryptionTest(_ encrypted: EncryptedDocument) {
        _ = try! BenchmarkTests.testClient.decrypt(encryptedDoc: encrypted, eakInfo: BenchmarkTests.testEak)
    }

    private func signatureTest(_ document: RecordData) {
        _ = try! BenchmarkTests.testClient.sign(document: document)
    }

    private func verificationTest(_ signed: SignedDocument<RecordData>) {
        _ = try! BenchmarkTests.testClient.verify(signed: signed, pubSigKey: BenchmarkTests.testEak.signerSigningKey!.ed25519)
    }

    // MARK: - Encryption Tests

    func testEncrypt1B() {
        measure { self.encryptionTest(BenchmarkTests.data1B) }
    }

    func testEncrypt500B() {
        measure { self.encryptionTest(BenchmarkTests.data500B) }
    }

    func testEncrypt250KB() {
        measure { self.encryptionTest(BenchmarkTests.data250KB) }
    }

    func testEncrypt500KB() {
        measure { self.encryptionTest(BenchmarkTests.data500KB) }
    }

    func testEncrypt1MB() {
        measure { self.encryptionTest(BenchmarkTests.data1MB) }
    }

    func testEncrypt2MB() {
        measure { self.encryptionTest(BenchmarkTests.data2MB) }
    }

    func testEncrypt8MB() {
        measure { self.encryptionTest(BenchmarkTests.data8MB) }
    }

    func testEncrypt16MB() {
        measure { self.encryptionTest(BenchmarkTests.data16MB) }
    }

    // MARK: - Decryption Tests

    func testDecrypt1B() {
        measure { self.decryptionTest(BenchmarkTests.rec1B) }
    }

    func testDecrypt500B() {
        measure { self.decryptionTest(BenchmarkTests.rec500B) }
    }

    func testDecrypt250KB() {
        measure { self.decryptionTest(BenchmarkTests.rec250KB) }
    }

    func testDecrypt500KB() {
        measure { self.decryptionTest(BenchmarkTests.rec500KB) }
    }

    func testDecrypt1MB() {
        measure { self.decryptionTest(BenchmarkTests.rec1MB) }
    }

    func testDecrypt2MB() {
        measure { self.decryptionTest(BenchmarkTests.rec2MB) }
    }

    func testDecrypt8MB() {
        measure { self.decryptionTest(BenchmarkTests.rec8MB) }
    }

    func testDecrypt16MB() {
        measure { self.decryptionTest(BenchmarkTests.rec16MB) }
    }

    // MARK: - Signature Tests

    func testSign1B() {
        measure { self.signatureTest(BenchmarkTests.data1B) }
    }

    func testSign500B() {
        measure { self.signatureTest(BenchmarkTests.data500B) }
    }

    func testSign250KB() {
        measure { self.signatureTest(BenchmarkTests.data250KB) }
    }

    func testSign500KB() {
        measure { self.signatureTest(BenchmarkTests.data500KB) }
    }

    func testSign1MB() {
        measure { self.signatureTest(BenchmarkTests.data1MB) }
    }

    func testSign2MB() {
        measure { self.signatureTest(BenchmarkTests.data2MB) }
    }

    func testSign8MB() {
        measure { self.signatureTest(BenchmarkTests.data8MB) }
    }

    func testSign16MB() {
        measure { self.signatureTest(BenchmarkTests.data16MB) }
    }

    // MARK: - Verification Tests

    func testVerify1B() {
        measure { self.verificationTest(BenchmarkTests.signed1B) }
    }

    func testVerify500B() {
        measure { self.verificationTest(BenchmarkTests.signed500B) }
    }

    func testVerify250KB() {
        measure { self.verificationTest(BenchmarkTests.signed250KB) }
    }

    func testVerify500KB() {
        measure { self.verificationTest(BenchmarkTests.signed500KB) }
    }

    func testVerify1MB() {
        measure { self.verificationTest(BenchmarkTests.signed1MB) }
    }

    func testVerify2MB() {
        measure { self.verificationTest(BenchmarkTests.signed2MB) }
    }

    func testVerify8MB() {
        measure { self.verificationTest(BenchmarkTests.signed8MB) }
    }

    func testVerify16MB() {
        measure { self.verificationTest(BenchmarkTests.signed16MB) }
    }

}
