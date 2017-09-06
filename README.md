# e3db-swift

Client SDK in Swift for Tozny's E3DB.

The Tozny End-to-End Encrypted Database (E3DB) is a storage platform with
powerful sharing and consent management features. [Read more on our blog](https://tozny.com/blog/announcing-project-e3db-the-end-to-end-encrypted-database/).

E3DB provides a familiar JSON-based NoSQL-style API for reading, writing, and
querying data stored securely in the cloud.

## Example

Get started by registering for a free account at [Tozny's Console](https://console.tozny.com).
Then create a **Client Registration Token** from the console and copy the token
value.

To run the example project, clone the repo, and run `pod install` from the
Example directory first.

Finally, paste the token value into the `ViewController.swift` source for the
line:

```swift
private let e3dbToken = "<PASTE_CLIENT_TOKEN_HERE>"
```

#### Register a New Client

Use the client token generated from the Tozny Console to register a new client:

```swift
import E3db

/// This is the main client performing E3db operations
var e3db: Client?

Client.register(token: e3dbToken, clientName: "ExampleApp") { (result) in
    switch result {

        // The operation was successful, here's the configuration
        case .success(let config):
            // create main E3db client with config
            self.e3db = Client(config: config)

        case .failure(let error):
            print("An error occurred attempting registration: \(error).")
        }
    }
}
```

#### Write a Record

Create a dictionary of `String` key-value pairs to store a record in E3db. The
keys of the dictionary will remain unencrypted, but the values will be encrypted
before ever leaving the device.

```swift
// Wrap message in RecordData type to designate
// it as sensitive information for encryption
let recordData = RecordData(cleartext: ["SSN": "123-45-6789"])

e3db?.write(type: "UserInfo", data: recordData, plain: ["Sent from": "my iPhone"]) { (result) in
    switch result {

        // The operation was successful, here's the record
        case .success(let record):

            // `record.meta` holds metadata associated
            // with the record, such as type.
            print("Wrote record! \(record.meta.recordId)")

        case .failure(let error):
            print("An error occurred attempting to write the data: \(error)")
        }
    }
}
```

#### Read a Record

You can request several records at once by specifying `QueryParams`, but if you
already have the `recordId` of the record you want to read, you can request it
directly.

```swift
// Perform read operation with the recordId of the
// written record, decrypting it after getting the
// encrypted data from the server.
e3db?.read(recordId: recordId) { (result) in
    switch result {

    // The operation was successful, here's the record
    case .success(let record):

        // The record returned contains the same dictionary
        // supplied to the `RecordData` struct during the write
        print("Record data: \(record.data)")

    case .failure(let error):
        print("An error occurred attempting to read the record: \(error)")
    }
}
```

## Requirements

- iOS 9.0+

## Installation

E3db is available through [CocoaPods](http://cocoapods.org). To install it,
simply add the following line to your Podfile:

```ruby
pod "E3db", :git => 'https://github.com/tozny/e3db-swift'
```

## Development

See the [Development Guide](dev/Development.md) for details on development.

## Author

Tozny

## License

Copyright © Tozny, LLC 2017. All rights reserved.
