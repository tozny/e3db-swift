 //
//  CryptoTests.swift
//  E3db_Tests
//

import XCTest
@testable import E3db

class CryptoTests: XCTestCase, TestUtils {

    func testFileEncryptDecryptEqual() {
        guard let srcUrl = FileManager.tempBinFile(),
              let dstUrl = FileManager.tempBinFile() else {
            return XCTFail("Could not open files")
        }
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
            try! FileManager.default.removeItem(at: dstUrl)
        }

        do {
            let data = Data(repeatElement("testing", count: 10).joined().utf8)
            try data.write(to: srcUrl)
            let accessKey = Crypto.generateAccessKey()!
            let encrypted = try Crypto.encrypt(fileAt: srcUrl, ak: accessKey)
            defer {
                try! FileManager.default.removeItem(at: encrypted.url)
            }
            try Crypto.decrypt(fileAt: encrypted.url, to: dstUrl, ak: accessKey)
            let input  = try FileHandle(forReadingFrom: dstUrl)
            let buffer = input.readDataToEndOfFile()
            input.closeFile()
            XCTAssertEqual(buffer, data)
        } catch {
            return XCTFail(error.localizedDescription)
        }
    }

    func testMD5() {
        guard let srcUrl = FileManager.tempBinFile() else {
            return XCTFail("Could not open file")
        }
        defer {
            try! FileManager.default.removeItem(at: srcUrl)
        }
        do {
            let data = Data(repeatElement("testing", count: 10).joined().utf8)
            try data.write(to: srcUrl)
            let expected = "DPb7oJVFD4O0cXsAkVRltA=="
            let actual   = try Crypto.md5(of: srcUrl)
            XCTAssertEqual(expected, actual)
        } catch {
            return XCTFail(error.localizedDescription)
        }
    }

}
