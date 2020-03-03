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

    var config: Config!
    var idConfig: IdentityConfig!
    var identity: PartialIdentity!
    var validApplication: Application!

    let validUsername = "test5@example.com"
    let validPass = "pass"
    let regToken = "cf5d284f7f003ecd449fdc888fa63552d5fba998f5cfc4774618101e5bce5950"


    override func setUp() {
        super.setUp()
        config = Config(clientName: "local",
                        clientId: UUID(uuidString: "f46d8ca8-5d2e-4fd9-b063-68765f6b6ca7")!,
                        apiKeyId: "68997273f0d73d6768c9e001544a351341e275df192a672c8d300621c3d5b2b6",
                        apiSecret: "05abbc1e59587546672fbdb228017d5318d485c09298325753a044ff002ecc7e",
                        publicKey: "hRfXS_jwJCWx5Pu9Thug0ng3OzDs9YQd88cXbCfo6iQ",
                        privateKey: "mp6rwkXTspV-rUWLmsXJwuC7zjnKBQjwcn645l_mjR4",
                        baseApiUrl: URL(string: "https://tozauthtest.ngrok.io")!,
                        publicSigKey: "vrMzlpNeFJwufgpx2HPDtx-ZcR9tCngFH0wwSqUobqs",
                        privateSigKey: "k4RxD58X8r--adqPyqQ5_leLcrSHizg2ywBTiqgjnIu-szOWk14UnC5-CnHYc8O3H5lxH20KeAUfTDBKpShuqw")

        validApplication = Application(apiUrl: "https://tozauthtest.ngrok.io",
                                       appName: "account",
                                       realmName: "new",
                                       brokerTargetUrl: "hello")

        idConfig = IdentityConfig(realmName: "new",
                                  appName: "account",
                                  apiUrl: "https://tozauthtest.ngrok.io",
                                  username: "test4@example.com",
                                  brokerTargetUrl: "http://localhost:8080",
                                  storageConfig: config)

        identity = PartialIdentity(idConfig: idConfig)
    }

    override func tearDown() {
        super.tearDown()
        config = nil
    }

    func emptyActionHandler(loginAction:IdentityLoginAction) -> [String:String] {
        return [:]
    }

    func testSortQueryParameters() {
        let unsortedQuery = "e=f&a=b&c=d"
        let sortedQuery = E3db.sortQueryParameters(query: unsortedQuery)
        let expectedQuery = "a=b&c=d&e=f"
        XCTAssertEqual(sortedQuery, expectedQuery)
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
        let someData:[String: String] = ["what":"okay"]

        let writeExpectation = self.expectation(description: "written")
        let readExpectation = self.expectation(description: "read")

        identity.storeClient.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: nil) {
            result in
            switch (result) {
            case .failure(let error):
                XCTFail("failure found on writing: \(error)")
                break
            case .success(let note):
                writeExpectation.fulfill()
                guard let noteID = note.noteID else {
                    break
                }
                Client.readNote(noteID: noteID, privateEncryptionKey: self.config.privateKey, publicEncryptionKey: self.config.publicKey, publicSigningKey: self.config.publicSigKey, privateSigningKey: self.config.privateSigKey, apiUrl: self.config.baseApiUrl.absoluteString) {
                    result in
                    switch (result){
                    case .success(let note):
                        XCTAssert(note.data["what"] == "okay")
                        readExpectation.fulfill()
                        break
                    case .failure(let error):
                        XCTFail("this is the error found \(error)")
                        break
                    }
                }
                break
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testWriteNote() {
        let someData:[String: String] = ["what":"okay"]
        let expectation = self.expectation(description: "written")
        identity.storeClient.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: nil) {
            result in
            switch (result) {
            case .failure(let error):
                XCTFail("Error writing: \(error)")
                break
            case .success(let note):
                XCTAssert(note.data["what"] != "okay")
                expectation.fulfill()
                break
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testStaticWriteNote() {
        let someData:[String: String] = ["what":"okay"]
        let expectation = self.expectation(description: "written")
        Client.writeNote(data: someData,
                           recipientEncryptionKey: self.config.publicKey,
                           recipientSigningKey: self.config.publicSigKey,
                           privateEncryptionKey: self.config.privateKey,
                           publicEncryptionKey: self.config.publicKey,
                           publicSigningKey: self.config.publicSigKey,
                           privateSigningKey: self.config.privateSigKey,
                           apiUrl: self.config.baseApiUrl.absoluteString,
                           options: nil) {

            result in
            switch (result) {
            case .failure(let error):
                XCTFail("Error writing: \(error)")
                break
            case .success(let note):
                XCTAssert(note.data["what"] != "okay")
                expectation.fulfill()
                break
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testReadNoteByName() {
        let someData:[String: String] = ["what":"okay"]

        let writeExpectation = self.expectation(description: "written")
        let readExpectation = self.expectation(description: "read")

        let noteName = UUID.init().uuidString
        let noteOptions = NoteOptions(IdString: noteName, maxViews: -1, expires: false, eacp: nil)
        identity.storeClient.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: noteOptions) {
            result in
            switch (result) {
            case .failure(let error):
                XCTFail("error writing: \(error)")
                break
            case .success(let note):
                XCTAssert(note.data["what"] != "okay")
                self.identity.storeClient.readNoteByName(noteName: noteName) {
                    result in
                    switch (result){
                    case .success(let note):
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

    func testRegisterIdentity() {
        let registerExpectation = self.expectation(description: "registered")

        let username = UUID.init().uuidString
        let password = UUID.init().uuidString

        self.validApplication.register(username: username, password: password, email: username, token: regToken) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success:
                registerExpectation.fulfill()
                break
            }
        }
        waitForExpectations(timeout: 5)
    }

//    func testRegisterIdentityLive() {
//        let application = Application(apiUrl: "https://dev.e3db.com", appName: "account", realmName: "swift", brokerTargetUrl: "https://dev.id.tozny.com/swift/recover")
//        let regToken = "e06fae4baffd6148e5081d22f2c73fe11706d7347c9174c49c171f4cc794e745"
//
//        let registerExpectation = self.expectation(description: "registered")
//
//        var username = ""
//        username = UUID.init().uuidString + "-michael@example.com"
////        username = "willmichael+10@tozny.com"
//
//        let password = "pass"
//
//        print("username \(username)")
//
//        application.register(username: username, password: password, email: username, token: regToken) {
//            result -> Void in
//            switch(result) {
//            case .failure(let error):
//                XCTFail("Found error when registering \(error)")
//                break
//            case .success(let identity):
//                registerExpectation.fulfill()
//                print("success config \(identity.idConfig)")
//                print("success store \(identity.storeClient.config.publicSigKey)")
//                break
//            }
//        }
//        waitForExpectations(timeout: 5)
//    }

    func testLogin() {
        let loginExpectation = self.expectation(description: "login")

        self.validApplication.login(username: self.validUsername, password: self.validPass, actionHandler: self.emptyActionHandler) {
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
        waitForExpectations(timeout: 5)
    }

//    func testInitiateBrokerEmailRecovery() {
////        let application = Application(apiUrl: "https://dev.e3db.com", appName: "account", realmName: "swift", brokerTargetUrl: "https://dev.e3db.com/swift/recover")
//        let recoveryExpectation = self.expectation(description: "login")
//        validApplication.initiateBrokerLogin(username: validUsername) {
//            result -> Void in
//            switch(result) {
//            case .failure(let error):
//                XCTFail("Found error when initiating broker login \(error)")
//                break
//            case .success:
//                recoveryExpectation.fulfill()
//                break
//            }
//        }
//        waitForExpectations(timeout: 2)
//    }

//    func testCompleteBrokerEmailRecovery() {
//        let application = Application(apiUrl: "https://dev.e3db.com", appName: "account", realmName: "swift", brokerTargetUrl: "https://dev.e3db.com/swift/recover")
//        let recoveryExpectation = self.expectation(description: "login")
//        let otp = "XgTNc7ar1RhSq5lLSKenjc77oMtwNgUN1ZAUTTgEH1I"
//        let noteId = "7654df53-94dc-4eb9-aad4-09ecf36b5d77"
//        application.completeEmailRecovery(otp: otp, noteID: noteId, recoveryUrl: nil) {
//            result -> Void in
//            switch(result) {
//            case .failure(let error):
//                XCTFail("Found error when logging in \(error)")
//                break
//            case .success(let partial):
//                print("hey we succeeded \(partial)")
//                recoveryExpectation.fulfill()
//                break
//            }
//        }
//        waitForExpectations(timeout: 200)
//    }
//
//    func testCompleteBrokerOTPRecovery() {
//        let application = Application(apiUrl: "https://dev.e3db.com", appName: "account", realmName: "swift", brokerTargetUrl: "https://dev.e3db.com/swift/recover")
//        let recoveryExpectation = self.expectation(description: "login")
//        let otp = "PsEzqXRlTKustyj4EMrMjYfcoeR0ZlIjAmVeAWdRM-I"
//        let noteId = "5b6b4d04-d16b-44ff-be54-23ec8d882341"
//        application.completeOTPRecovery(otp: otp, noteId: noteId) {
//            result -> Void in
//            switch(result) {
//            case .failure(let error):
//                XCTFail("Found error when logging in \(error)")
//                break
//            case .success(let partial):
//                print("hey we succeeded \(partial)")
//                recoveryExpectation.fulfill()
//                break
//            }
//        }
//        waitForExpectations(timeout: 200)
//    }

    func testFetchToken() {
        let registerExpectation = self.expectation(description: "registered")
        let tokenExpectation = self.expectation(description: "token")

        var username = ""
        username = UUID.init().uuidString + "-michael@example.com"

        let password = "pass"

        validApplication.register(username: username, password: password, email: username, token: regToken) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success(let identity):
                registerExpectation.fulfill()
                identity.fetchToken(appName: "account") {
                    result -> Void in
                    switch(result) {
                    case .failure(let error):
                        XCTFail("couldn't fetch token: \(error)")
                        break
                    case .success:
                        tokenExpectation.fulfill()
                    }
                }
                break
            }
        }
        waitForExpectations(timeout: 5)
    }

    func testReplaceNoteByName() {
        let someData:[String: String] = ["what":"okay"]
        let newData = ["hello":"goodbye"]

        let writeExpectation = self.expectation(description: "written")
        let readExpectation = self.expectation(description: "read")
        let changeExpectation = self.expectation(description: "changed")

        let noteName = UUID.init().uuidString
        let noteOptions = NoteOptions(IdString: noteName, maxViews: -1, expires: false, eacp: nil)
        identity.storeClient.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: noteOptions) {
            result in
            switch (result) {
            case .failure(let error):
                XCTFail("error writing \(error)")
                break
            case .success:
                writeExpectation.fulfill()
                self.identity.storeClient.replaceNoteByName(data: newData, recipientEncryptionKey: self.config.publicKey, recipientSigningKey: self.config.publicSigKey, options: noteOptions) {
                    result in
                    switch (result) {
                    case .failure(let error):
                        XCTFail("error rewriting note \(error)")
                        break
                    case .success:
                        changeExpectation.fulfill()
                        Client.readNoteByName(noteName: noteName,
                                                privateEncryptionKey: self.config.privateKey,
                                                publicEncryptionKey: self.config.publicKey,
                                                publicSigningKey: self.config.publicSigKey,
                                                privateSigningKey: self.config.privateSigKey,
                                                additionalHeaders: ["empty": "header"],
                                                apiUrl: "https://tozauthtest.ngrok.io") {
                            result in
                            switch (result) {
                            case .failure(let error):
                                XCTFail("error reading \(error)")
                                break
                            case .success(let note):
                                XCTAssert(note.data["hello"] == "goodbye")
                                readExpectation.fulfill()
                                break
                            }
                        }
                    }
                }
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }


    func testChangePassword() {
        let registerExpectation = self.expectation(description: "registered")
        let passChangeExpectation = self.expectation(description: "passChanged")
        let loginFailExpectation = self.expectation(description: "loginFailExpectation")

        var username = ""
        username = UUID.init().uuidString + "-michael@example.com"

        let password = "pass"
        let newPass = "newPass"

        func actionHandler(loginAction:IdentityLoginAction) -> [String:String] {
            return [:]
        }

        validApplication.register(username: username, password: password, email: username, token: regToken) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success(let identity):
                registerExpectation.fulfill()
                identity.changePassword(newPassword: newPass) {
                    result in
                    switch(result) {
                    case .failure(let error):
                        XCTFail("Couldn't change password \(error)")
                        break
                    case .success:
                        passChangeExpectation.fulfill()
                        self.validApplication.login(username: username, password: password, actionHandler: actionHandler) {
                            result in
                            let failLogin = try? result.get()
                            if failLogin != nil {
                                XCTFail("Login should've failed because we changed password")
                                return
                            }
                            loginFailExpectation.fulfill()
                        }
                    }
                }
            }
        }
        waitForExpectations(timeout: 5)
    }

    func testGetKeycloakToken() {
        let loginExpectation = self.expectation(description: "login")
        self.validApplication.login(username: self.validUsername, password: self.validPass, actionHandler: self.emptyActionHandler) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when logging in \(error)")
                break
            case .success(let identity):
                identity.token() {
                    result in
                    switch(result) {
                    case .failure(let error):
                        XCTFail("Couldn't get token \(error)")
                        break
                    case.success:
                        loginExpectation.fulfill()
                    }
                }
            }
        }
        waitForExpectations(timeout: 5)
    }
}

