//
//  IdentityTests.swift
//  E3db_Tests
//

import Foundation
import XCTest
import Sodium
@testable import E3db

class IdentityTests: XCTestCase, TestUtils {

    var config: Config!
    var idConfig: IdentityConfig!
    var identity: PartialIdentity!
    var validApplication: Application!
    var validUsername: String!
    var validPass: String!
    var regToken: String!


    override func setUp() {
        super.setUp()
        // Initialize valid values for all above config

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
    
    func testReadNote() {
        let someData:[String: String] = ["test":"data"]

        let writeExpectation = self.expectation(description: "written")
        let readExpectation = self.expectation(description: "read")

        identity.storeClient.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: nil) {
            result in
            switch (result) {
            case .failure:
                break
            case .success(let note):
                writeExpectation.fulfill()
                guard let noteID = note.noteID else {
                    XCTFail("Failed to get noteID")
                    return
                }
                self.identity.storeClient.readNote(noteID: noteID) {
                    result in
                    switch (result){
                    case .failure(let error):
                        XCTFail("Failed to read note \(error)")
                        break
                    case .success(let note):
                        XCTAssert(note.data["test"] == "data")
                        readExpectation.fulfill()
                        break
                    }
                }
                break
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }


    func testStaticReadNote() {
        let someData:[String: String] = ["test":"data"]

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
                        XCTAssert(note.data["test"] == "data")
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
        let someData:[String: String] = ["test":"data"]
        let expectation = self.expectation(description: "written")
        identity.storeClient.writeNote(data: someData, recipientEncryptionKey: config.publicKey, recipientSigningKey: config.publicSigKey, options: nil) {
            result in
            switch (result) {
            case .failure(let error):
                XCTFail("Error writing: \(error)")
                break
            case .success(let note):
                XCTAssert(note.data["test"] != "data")
                expectation.fulfill()
                break
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testStaticWriteNote() {
        let someData:[String: String] = ["test":"data"]
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
                XCTAssert(note.data["hat"] != "okay")
                expectation.fulfill()
                break
            }
        }
        waitForExpectations(timeout: 5, handler: nil)
    }

    func testReadNoteByName() {
        let someData:[String: String] = ["test":"data"]

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
                XCTAssert(note.data["test"] != "data")
                self.identity.storeClient.readNoteByName(noteName: noteName) {
                    result in
                    switch (result){
                    case .success(let note):
                        XCTAssert(note.data["test"] == "data")
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

    func testRegisterAndLogin() {
        let loginExpectation = self.expectation(description: "login")
        let registerExpectation = self.expectation(description: "registered")

        let username = UUID.init().uuidString + "10@tozny.com"
        let password = UUID.init().uuidString

        print("username \(username)")
        print("pass \(password)")

        self.validApplication.register(username: username, password: password, email: username, token: regToken) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success:
                registerExpectation.fulfill()
                self.validApplication.login(username: username, password: password, actionHandler: self.emptyActionHandler) {
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
                break
            }
        }
        waitForExpectations(timeout: 5)
    }

    func testFetchToken() {
        let loginExpectation = self.expectation(description: "login")
        let tokenExpectation = self.expectation(description: "token")

        validApplication.login(username: validUsername, password: validPass, actionHandler: emptyActionHandler) {
            result -> Void in
            switch(result) {
            case .failure(let error):
                XCTFail("Found error when registering \(error)")
                break
            case .success(let identity):
                loginExpectation.fulfill()
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
        let someData:[String: String] = ["test":"data"]
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

