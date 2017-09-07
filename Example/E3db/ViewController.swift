//
//  ViewController.swift
//  E3db
//

import UIKit
import E3db

// Create an account and generate
// a client token from https://console.tozny.com
private let e3dbToken = ""

class ViewController: UIViewController {

    @IBOutlet weak var messageView: UITextView!
    @IBOutlet weak var responseLabel: UILabel!

    /// This is the main client performing E3db operations
    var e3db: Client?

    /// We'll use this to identify the most recently written record
    var latestRecordId: UUID?


    /// Demonstrates client registration,
    /// and storing and loading client configuration
    override func viewDidLoad() {
        super.viewDidLoad()

        // load E3db configuration under default profile name from keychain
        if let config = Config() {
            e3db = Client(config: config)
            return
        }

        // make sure a client token exists
        guard e3dbToken.count > 0 else {
            return print("Please register an account at https://console.tozny.com/ and generate a client token!")
        }

        // No client previously registered on this device,
        // use the client token to register.
        Client.register(token: e3dbToken, clientName: "ExampleApp") { (result) in
            switch result {

            // The operation was successful, here's the configuration
            case .success(let config):
                // create main E3db client with config
                self.e3db = Client(config: config)

                // save test config under default profile name, protects it in secure enclave w/ TouchID
                guard config.save() else {
                    return print("Could not save config")
                }

            case .failure(let error):
                print("An error occurred attempting registration: \(error).")
            }
        }
    }




    /// Demonstrates writing data securely to E3db.
    /// The `write` operation will encrypt the secret message
    /// before it leaves the device, ensuring End-to-End Encryption
    @IBAction func write() {
        guard let msg = messageView.text else {
            return print("Text field contains no text")
        }

        // Wrap message in RecordData type to designate
        // it as sensitive information for encryption
        let recordData = RecordData(cleartext: ["secret message": msg])

        // Perform write operation, providing a user-defined type,
        // the message, and any other non-sensitive information to associate with the data
        e3db?.write(type: "my secret message", data: recordData, plain: ["Sent from": "my iPhone"]) { (result) in
            let text: String
            switch result {

            // The operation was successful, here's the record
            case .success(let record):

                // `record.meta` holds metadata assoociated
                // with the record, such as type. We'll use
                // the `recordId` to help identify it later
                self.latestRecordId = record.meta.recordId
                text = "Wrote record! \(record.meta.recordId)"

            case .failure(let error):
                text = "An error occurred attempting to write the data: \(error)"
            }

            // Present response
            print(text)
            self.responseLabel.text = text
        }
    }


    /// Demonstrates reading data securely from E3db.
    /// The `read` operation will decrypt the secret message
    /// using the user's key, ensuring End-to-End Encryption
    @IBAction func read() {
        guard let recordId = latestRecordId else {
            return print("No records have been written yet.")
        }

        // Perform read operation with the recordId of the
        // written record, decrypting it after getting the
        // encrypted data from the server.
        e3db?.read(recordId: recordId) { (result) in
            let text: String
            switch result {

            // The operation was successful, here's the record
            case .success(let record):

                // The record returned contains the same dictionary
                // supplied to the `RecordData` struct during the write
                text = "Record data: \(record.data)"

            case .failure(let error):
                text = "An error occurred attempting to read the record: \(error)"
            }

            // Present response
            print(text)
            let alert = UIAlertController(title: "Decrypted Record", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default))
            self.present(alert, animated: true)
        }
    }
}

