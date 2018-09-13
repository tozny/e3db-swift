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

// This is the main client performing E3db operations
// (for the remaining examples, we'll assume a non-optional client instance)
var e3db: Client?

Client.register(token: e3dbToken, clientName: "ExampleApp") { result in
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

// Can optionally include arbitrary metadata as `plain`
// where neither keys nor values are encrypted
e3db.write(type: "UserInfo", data: recordData, plain: ["Sent from": "my iPhone"]) { result in
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
e3db.read(recordId: recordId) { result in
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
e3db.query(params: q1) { result in
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
e3db.query(params: q2) { result in
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
e3db.share(type: "UserInfo", readerId: otherClient) { result in
    guard case .success = result else {
        return print("An error occurred attempting to grant access to records: \(result.error)")
    }
    // Sharing was successful!
}

// Remove access to "UserInfo" records from the given client
e3db.revoke(type: "UserInfo", readerId: otherClient) { result in
    guard case .success = result else {
        return print("An error occurred attempting to revoke access to records: \(result.error)")
    }
    // Revoking was successful!
}
```

#### Authorizers

Every E3DB client can authorize any other client to share data on their behalf.
That is, the data producer does not need to be the sole entity that enables
sharing with other clients. We call the client that is allowed to share data on
a data producer's behalf the "authorizer".

Just like `share`, authorization is granted based on record types. That is, a
client can only authorize another client to share a specific record type. There
is no mechanism to grant sharing of all record types (whether any exist or not).

Note that the authorizer does *not* have permission to read the data shared
themselves - they are only allowed to share data on behalf of the data producer.

To add an authorizer, use the `add(authorizerId:type:completion:)` method:

```swift
let authorizerId = // ID of client to share on this data producer's behalf
let recordType   = // type of records to authorize

e3db.add(authorizerId: authorizerId, type: recordType) { result in
    guard case .success = result else {
        return print("An error occurred attempting to grant authorizer privilege: \(result.error)")
    }
    // client successfully authorized
}
```

Authorization can be removed with the `remove(authorizerId:...` methods.
Authorization *can* be removed for all record types, or for a single record
type.

A client can list all clients that it has authorized to share on its behalf
using the `add(authorizerId:type:completion:)` method. Similarly, a client can
determine all the data producers that it can share on behalf of using the
`getAuthorizedBy` method.

#### Sharing as an Authorizer
A client that has been given permission to share records on behalf of a writer
can use the `share(onBehalfOf:type:readerId:completion:)` method:

```swift
let writerId   = // ID of data writer
let readerId   = // ID of client we are sharing with
let recordType = // type of records to share

e3db.share(onBehalfOf: writerId, type: recordType, readerId: readerId) { result in
    guard case .success = result else {
        return print("An error occurred attempting to share: \(result.error)")
    }
    // successfully shared
}
```

#### Local Encryption & Decryption

The E3DB SDK allows you to encrypt documents for local storage, which can
be decrypted later, by the client that created the document or any client with
which the document has been `shared`. Note that locally encrypted documents
_cannot_ be written directly to E3DB -- they must be decrypted locally and
written using the `write` or `update` methods.

Local encryption (and decryption) requires two steps:

1. Create a 'writer key' (for encryption) or obtain a 'reader key' (for
  decryption).
2. Call `encrypt` to encrypt a new document. For decryption, call `decrypt`.

The 'writer key' and 'reader key' are both `EAKInfo` objects. An `EAKInfo`
object holds an encrypted key that can be used by the intended client to encrypt
or decrypt associated documents. A writer key can be created by calling
`createWriterKey`; a 'reader key' can be obtained by calling `getReaderKey`.
(Note that the client calling `getReaderKey` will only receive a key if the
writer of those records has given access to the calling client through the
`share` operation.)

The `createWriterKey` and `getReaderKey` are networked operations, (which means
they are asynchronous operations as well), but can be performed once ahead of
time. The `EAKInfo` instances returned from those operations are safe to store
locally, and can be used in the non-networked operations of `encrypt` and
`decrypt`.

Here is an example of encrypting a document locally:

```swift
let recordData = RecordData(cleartext: ["SSN": "123-45-6789"])
let recordType = "UserInfo"

e3db.createWriterKey(type: type) { result in
    switch result {
    // The operation was successful, here's the `EAKInfo` instance,
    // you can think of this as the "encryption key", but it's also encrypted,
    // so you don't have to worry about storing it in plaintext or exposing it.
    case .success(let eak):
        // attempt to create an encrypted document with the EAKInfo
        let encrypted = try? self.e3db.encrypt(type: recordType, data: recordData, eakInfo: eak)
        print("Encrypted document: \(encrypted!)")

    case .failure(let error):
        print("An error occurred attempting to create writer key: \(error)")
    }
}
```

(Note that the `EAKInfo` instance is safe to store with the encrypted data, as
it is also encrypted). The client can decrypt the given record as follows:

```swift
let encrypted = // get encrypted document (e.g. read from local storage)
let writerKey = // get stored EAKInfo instance (e.g. from local storage)

// attempt to decrypt an encrypted document with the EAKInfo instance
let decrypted = try e3db.decrypt(encryptedDoc: encrypted, eakInfo: writerKey)
print("Decrypted document: \(decrypted!)")  
```

##### Local Decryption of Shared Records

When two clients have a sharing relationship, the 'reader' can locally decrypt
any documents encrypted by the 'writer,' without using E3DB for storage.

* The 'writer' must first share records with a 'reader', using the `share`
method.
* The 'reader' must then obtain a reader key using `getReaderKey`.

Note that these are networked operations. However, the `EAKInfo` instance can be
saved for later use.

```swift
let encrypted  = // get encrypted document (e.g. read from local storage)
let writerID   = // ID of writer that produced record
let recordType = "UserInfo"
var eakInfo: EAKInfo?

e3db.getReaderKey(writerId: writerID, userId: writerID, type: recordType) { result in
    switch result {
    // The operation was successful, here's the `EAKInfo` instance,
    // you can think of this as the "encryption key", but it's also encrypted,
    // so you don't have to worry about storing it in plaintext or exposing it.
    case .success(let eak):
      self.eakInfo = eak

    case .failure(let error):
        print("An error occurred attempting to get reader key: \(error)")
    }
}
```

The `EAKInfo` type conforms to Swift's `Codable` protocol for easy
serialization, e.g. for saving to `UserDefaults`:

```swift
// store in UserDefaults
// assumes eakInfo is a non-optional `EAKInfo` instance
let eakData = try JSONEncoder().encode(eakInfo)
UserDefaults.standard.set(eakData, forKey: "myReaderKey")
```
```swift
// retrieve from UserDefaults
guard let eakData = (UserDefaults.standard.value(forKey: "myReaderKey") as? Data) else {
    return print("Could not retrieve eak data from defaults")
}

// deserialize into eakInfo
let eakInfo = try JSONDecoder().decode(EAKInfo.self, from: eakData)
```

After obtaining a reader key, the 'reader' can then decrypt any
records encrypted by the writer as follows:

```swift
// attempt to decrypt an encrypted document with the EAKInfo instance
let decrypted = try e3db.decrypt(encryptedDoc: encrypted, eakInfo: eakInfo)
print("Decrypted document: \(decrypted)")  
```

#### Document Signing & Verification

Every E3DB client created with this SDK is capable of signing documents and
verifying the signature associated with a document. By attaching signatures to
documents, clients can be confident in:

  * Document integrity - the document's contents have not been altered (because
    the signature will not match).
  * Proof-of-authorship - The author of the document held the private signing
    key associated with the given public key when the document was created.

Signatures require the target type to conform to the `Signable` protocol. This
protocol requires one method to be implemented:
```swift
func serialized() -> String
```

This method must provide a reproducible string representation of the data to
sign and verify. This requires the serialization to be deterministic -- i.e.
types such as `Dictionary` and `Set` must be serialized in a reproducible order.

The E3db types of `EncryptedDocument` and `SignedDocument` conform to the
`Signable` protocol.

To create a signature, use the `sign` method. (This example assumes an encrypted
document as create above):

```swift
let encrypted = // get encrypted document (or anything that conforms to `Signable`)
let signedDoc = try e3db.sign(document: encrypted)
print("Signed Document: \(signedDoc)")
```

To verify a document, use the `verify` method. Here, we use the same `signedDoc`
instance as above. `config` holds the private & public keys for the client.
(Note that, in general, `verify` requires the public signing key of the client
that wrote the record):

```swift
guard try e3db.verify(signed: signed, pubSigKey: config.publicSigKey)) else {
    return print("Document failed verification")
}
// Document verified!
```

### Certificate Pinning

If desired, E3DB Clients can be provided with a `URLSession` instance. This can
allow custom configuration for networked calls, including pinning TLS sessions
to trusted certificate(s).

Simply supply a pre-configured `URLSession` to either the `Client.register` or
the `Client.init` methods.

```swift
let config  = // load config from secure storage

// set custom delegate
let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
let e3db    = Client(config: config, urlSession: session)
```

The following shows an example of how to use the `URLSessionDelegate` callback
to restrict network activity to an intermediate certificate in a cert chain.

```swift
func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    // Adapted from OWASP https://www.owasp.org/index.php/Certificate_and_Public_Key_Pinning#iOS
    let cancel = URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge

    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          SecTrustEvaluate(trust, nil) == errSecSuccess,
          let serverCert = SecTrustGetCertificateAtIndex(trust, 1) else { // checks intermediate cert (index 1)
            return completionHandler(cancel, nil)
    }

    let pinnedCertData = loadTrustedCertData() // load cert (e.g. from file)
    let serverCertData = SecCertificateCopyData(serverCert) as Data

    guard pinnedCertData == serverCertData else {
        return completionHandler(cancel, nil)
    }

    // pinning succeeded
    completionHandler(.useCredential, URLCredential(trust: trust))
}
```