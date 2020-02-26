//
//  IdentityTests.swift
//  E3db_Tests
//
//  Created by michael lee on 2/13/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import Foundation
//
//  IdentityTests.swift
//  E3db_Example
//
//  Created by michael lee on 2/13/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import XCTest
import Sodium
@testable import E3db

class IdentityTests: XCTestCase, TestUtils {
    
    let config = Config(clientName: "local", clientId: UUID(uuidString: "f46d8ca8-5d2e-4fd9-b063-68765f6b6ca7")!, apiKeyId: "68997273f0d73d6768c9e001544a351341e275df192a672c8d300621c3d5b2b6", apiSecret: "05abbc1e59587546672fbdb228017d5318d485c09298325753a044ff002ecc7e", publicKey: "hRfXS_jwJCWx5Pu9Thug0ng3OzDs9YQd88cXbCfo6iQ", privateKey: "mp6rwkXTspV-rUWLmsXJwuC7zjnKBQjwcn645l_mjR4", baseApiUrl: URL(string: "https://tozauthtest.ngrok.io")!, publicSigKey: "vrMzlpNeFJwufgpx2HPDtx-ZcR9tCngFH0wwSqUobqs", privateSigKey: "k4RxD58X8r--adqPyqQ5_leLcrSHizg2ywBTiqgjnIu-szOWk14UnC5-CnHYc8O3H5lxH20KeAUfTDBKpShuqw")

    func testSortQueryParameters() {
        let unsortedQuery = "e=f&a=b&c=d"
        let sortedQuery = E3db.sortQueryParameters(query: unsortedQuery)
        let expectedQuery = "a=b&c=d&e=f"
        XCTAssertEqual(sortedQuery, expectedQuery)
    }
    
    func testDeriveNoteCreds() {
        // TODO?
    }
    
//    func testReadNote() {
//        let urlSession = URLSession.shared
//        let identity = Identity(config: config, urlSession: urlSession)
//
//        var someData:[String: String] = [:]
//        someData["what"] = "okay"
//
//
//        let writeExpectation = self.expectation(description: "written")
//        let readExpectation = self.expectation(description: "read")
//
//
//        identity.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: nil) {
//            result in
//            switch (result) {
//            case .failure:
//                break
//            case .success(let note):
//                writeExpectation.fulfill()
//                print("this is the note \(String(describing: note.noteID))")
//                guard let noteID = note.noteID else {
//                    break
//                }
//                identity.readNote(noteID: noteID) {
//                    result in
//                    switch (result){
//                    case .success(let note):
//                        print("this is note \(note.data)")
//                        XCTAssert(note.data["what"] == "okay")
//                        readExpectation.fulfill()
//                        break
//                    case .failure(let error):
//                        print("this is the error found \(error)")
//                        break
//                    }
//                }
//                break
//            }
//        }
//
//        waitForExpectations(timeout: 5, handler: nil)
//    }
//
//
    func testStaticReadNote() {
//        let urlSession = URLSession.shared
        let idConfig = IdentityConfig(realmName: "new", appName: "account", apiUrl: "https://tozauthtest.ngrok.io", username: "test4@example.com", storageConfig: config)
        let identity = PartialIdentity(idConfig: idConfig)


        var someData:[String: String] = [:]
        someData["what"] = "okay"


        let writeExpectation = self.expectation(description: "written")
        let readExpectation = self.expectation(description: "read")


        print("whats")
        identity.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: nil) {
            result in
            switch (result) {
            case .failure(let error):
                print("failure found on writing\(error)")
                break
            case .success(let note):
                writeExpectation.fulfill()
                print("this is the note \(String(describing: note.noteID))")
                guard let noteID = note.noteID else {
                    break
                }
                Identity.readNote(noteID: noteID, privateEncryptionKey: self.config.privateKey, publicEncryptionKey: self.config.publicKey, publicSigningKey: self.config.publicSigKey, privateSigningKey: self.config.privateSigKey, apiUrl: self.config.baseApiUrl.absoluteString) {
                    result in
                    switch (result){
                    case .success(let note):
                        print("this is note data \(note.data)")
                        XCTAssert(note.data["what"] == "okay")
                        readExpectation.fulfill()
                        break
                    case .failure(let error):
                        print("this is the error found \(error)")
                        break
                    }
                }
                break
            }
        }

        waitForExpectations(timeout: 5, handler: nil)
    }
//
//    func testWriteNote() {
//        let urlSession = URLSession.shared
//        let identity = Identity(config: config, urlSession: urlSession)
//        var someData:[String: String] = [:]
//        someData["what"] = "okay"
//        let expectation = self.expectation(description: "written")
//        identity.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: nil) {
//            result in
//            switch (result) {
//            case .failure(let error):
//                print("we found and error \(error)")
//                break
//            case .success(let note):
//                print("this is our encrypted note \(note)")
//                XCTAssert(note.data["what"] != "okay")
//                expectation.fulfill()
//                break
//            }
//        }
//
//        waitForExpectations(timeout: 5, handler: nil)
//    }
//
//    func testStaticWriteNote() {
//        var someData:[String: String] = [:]
//        someData["what"] = "okay"
//        let expectation = self.expectation(description: "written")
//        Identity.writeNote(data: someData, recipientEncryptionKey: self.config.publicKey, recipientSigningKey: self.config.publicSigKey, privateEncryptionKey: self.config.privateKey, publicEncryptionKey: self.config.publicKey, publicSigningKey: self.config.publicSigKey, privateSigningKey: self.config.privateSigKey, baseApiUrl: self.config.baseApiUrl.absoluteString, options: nil) {
//            result in
//            switch (result) {
//            case .failure(let error):
//                print("we found and error \(error)")
//                break
//            case .success(let note):
//                print("this is our encrypted note \(note)")
//                XCTAssert(note.data["what"] != "okay")
//                expectation.fulfill()
//                break
//            }
//        }
//        waitForExpectations(timeout: 5, handler: nil)
//    }
//
    func testReadNoteByName() {
//        let urlSession = URLSession.shared
//        let identity = Identity(config: config, urlSession: urlSession)

        let idConfig = IdentityConfig(realmName: "new", appName: "account", apiUrl: "https://tozauthtest.ngrok.io", username: "someUser", storageConfig: config)
        let identity = PartialIdentity(idConfig: idConfig)

        var someData:[String: String] = [:]
        someData["what"] = "okay"


        let writeExpectation = self.expectation(description: "written")
        let readExpectation = self.expectation(description: "read")

        let noteName = UUID.init().uuidString

//        let tozIdEacp = TozIdEacp(realmName: "randomRealm")


        let noteOptions = NoteOptions(IdString: noteName, maxViews: -1, expires: false, eacp: nil)

        identity.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: noteOptions) {
            result in
            switch (result) {
            case .failure(let error):
                XCTFail("error writing: \(error)")
                break
            case .success(let note):
                print("this is our encrypted note \(note)")
                XCTAssert(note.data["what"] != "okay")

                Identity.readNoteByName(noteName: noteName,
                                        privateEncryptionKey: self.config.privateKey,
                                        publicEncryptionKey: self.config.publicKey,
                                        publicSigningKey: self.config.publicSigKey,
                                        privateSigningKey: self.config.privateSigKey,
                                        additionalHeaders: ["garbage": "lol"],
                                        apiUrl: "https://tozauthtest.ngrok.io") {
//                identity.readNoteByName(noteName: noteName) {
                    result in
                    switch (result){
                    case .success(let note):
                        print("this is note \(note.data)")
                        XCTAssert(note.data["what"] == "okay")
                        readExpectation.fulfill()
                        break
                    case .failure(let error):
                        XCTFail("error reading \(error)")
                        break
                    }
                }

                writeExpectation.fulfill()
                break
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testEmailEacpCoding() {
        let eacp = EmailEacp(emailAddress: "email", template: "template", providerLink: "link", defaultExpirationMinutes: 10)
        let encoded = try? JSONEncoder().encode(eacp)
        let encodedString = String(decoding: encoded!, as: UTF8.self)
        
        print("this is encoding string \(encodedString)")
    }


    func testRegisterIdentity() {
        let application = Application(apiUrl: "https://tozauthtest.ngrok.io", appName: "account", realmName: "company", brokerTargetUrl: "")
        let regToken = "77d41e3e9c38c08614a51a448fa4c2211b5e4d22da0938d9fb59379fefa89fff"

        let registerExpectation = self.expectation(description: "registered")

        let username = UUID.init().uuidString
        let password = UUID.init().uuidString

        application.register(username: username, password: password, email: username, token: regToken) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success:
                registerExpectation.fulfill()
                print("success")
                break
            }
        }

//        let urlSession = URLSession.shared
//        let identity = Identity(config: config, urlSession: urlSession)
//        try? identity.register(username: username, password: password, token: regToken, realmName: "company") {
//            result -> Void in
//                switch(result){
//                case .failure(let error):
//                    XCTFail("Found error when registering \(error)")
//                    break
//                case .success:
//                    registerExpectation.fulfill()
//                    print("success")
//                    break
//                }
//        }
        waitForExpectations(timeout: 5)
    }


    func testRegisterIdentityLocal() {
        let application = Application(apiUrl: "https://tozauthtest.ngrok.io", appName: "account", realmName: "new", brokerTargetUrl: "hello")
        let regToken = "cf5d284f7f003ecd449fdc888fa63552d5fba998f5cfc4774618101e5bce5950"

        let registerExpectation = self.expectation(description: "registered")

        var username = ""
        username = UUID.init().uuidString + "-michael@example.com"
        username = "test5@example.com"

        let password = "pass"

        print("username \(username)")

        application.register(username: username, password: password, email: username, token: regToken) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success(let identity):
                registerExpectation.fulfill()
                print("success config \(identity.idConfig)")
                print("success store \(identity.storeClient.config.publicSigKey)")
                break
            }
        }
        waitForExpectations(timeout: 5)
    }
    func testRegisterIdentityLive() {
        let application = Application(apiUrl: "https://dev.e3db.com", appName: "account", realmName: "swift", brokerTargetUrl: "https://dev.id.tozny.com/swift/recover")
        let regToken = "e06fae4baffd6148e5081d22f2c73fe11706d7347c9174c49c171f4cc794e745"

        let registerExpectation = self.expectation(description: "registered")

        var username = ""
        username = UUID.init().uuidString + "-michael@example.com"
//        username = "willmichael+10@tozny.com"

        let password = "pass"

        print("username \(username)")

        application.register(username: username, password: password, email: username, token: regToken) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success(let identity):
                registerExpectation.fulfill()
                print("success config \(identity.idConfig)")
                print("success store \(identity.storeClient.config.publicSigKey)")
                break
            }
        }
        waitForExpectations(timeout: 5)
    }

    func testLogin() {
        let application = Application(apiUrl: "https://tozauthtest.ngrok.io", appName: "account", realmName: "new", brokerTargetUrl: "hello")
        let username = "test5@example.com"
        let pass = "pass"


        let loginExpectation = self.expectation(description: "login")

        func actionHandler(loginAction:IdentityLoginAction) -> [String:String] {
            print("okay in login action")
            return ["what":"okay"]
        }

        application.login(username: username, password: pass, actionHandler: actionHandler) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when logging in \(error)")
                break
            case .success:
                loginExpectation.fulfill()
                break
            }
        }
        waitForExpectations(timeout: 10)
    }


    func testPbkdf2() {
        let result = try? Crypto.deriveCryptoKeys(password: "pass", salt: "test@test.com@realm:test")
        print("result \(result!)")
    }
}

