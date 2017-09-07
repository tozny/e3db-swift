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

## Requirements

- iOS 9.0+

## Installation

E3db is available through [CocoaPods](http://cocoapods.org). To install it,
simply add the following line to your Podfile:

```ruby
pod "E3db", :git => 'https://github.com/tozny/e3db-swift'
```

## Documentation

Full API documentation can be found [here](https://tozny.github.io/e3db-swift).
Code examples for the most common operations can be found below.

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

#### Query for Records

To request several records, and even filter on a set of optional parameters,
pass a `QueryParams` instance to the `query` method.

```swift
// Keep track of queried batches
var lastRead: Double?

// Construct query, filtering to:
// - return only 5 records at a time,
// - only "UserInfo" type records,
// - including records written by others
//   that have been shared with this client
let q1 = QueryParams(count: 5, types: ["UserInfo"], includeAllWriters: true)
e3db?.query(params: q1) { (result) in
    switch result {

    // The operation was successful, here's the `QueryResponse`,
    // which has the resulting records and an index for last record
    case .success(let resp):
        print("Records: \(resp.records)")
        lastRead = resp.last

    case .failure(let error):
        print("An error occurred attempting to query records: \(error)")
    }
}

// Query for next batch using `next`
let q2 = q1.next(after: lastRead!)
e3db?.query(params: q2) { (result) in
    // ...
}
```

Possible filters include:
- `count`: Limit the number of records returned by the query beyond the default
- `includeData`: Supply the full decrypted record data in the result records
- `writerIds`: Filter to records written by these IDs
- `userIds`: Filter to records with these user IDs
- `recordIds`: Filter to only the records identified by these IDs
- `types`: Filter to records that match the given types
- `after`: Number to facilitate paging the results -- used with the `last`
  property of the resulting `QueryResponse`
- `includeAllWriters`: Set this flag to include records that have been shared
  with you, defaults to `false`

#### Sharing

Records can be shared to allow other clients access. Grant clients read access
by specifying which client and which type of record `share`. Inversely, access
can be removed with the `revoke` method.

```swift
// Get the recipient client ID externally
let otherClient: UUID = ???

// Share records of type "UserInfo" with another client
e3db?.share(type: "UserInfo", readerId: otherClient) { (result) in
    guard case .success = result else {
        return print("An error occurred attempting to grant access to records: \(result.error)")
    }
    // Sharing was successful!
}

// Remove access to "UserInfo" records from the given client
e3db?.revoke(type: "UserInfo", readerId: otherClient) { (result) in
    guard case .success = result else {
        return print("An error occurred attempting to revoke access to records: \(result.error)")
    }
    // Revoking was successful!
}
```

If the other client has opted-in to discovery-by-email with E3db, variants exist
for sharing and revoking access that use their email address instead of their
client ID:
- `share(type:readerEmail:completion:)` for granting access via email
- `revoke(type:readerEmail:completion:)` for removing access via email

## Development

See the [Development Guide](dev/Development.md) for details on development.

## Author

Tozny

## License

Copyright © Tozny, LLC 2017. All rights reserved.
