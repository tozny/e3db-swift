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
private let E3dbToken = ""
```

## Requirements

- iOS 9.0+

## Installation

E3db is available through [CocoaPods](http://cocoapods.org). To install it,
simply add the following line to your Podfile:

```ruby
pod "E3db", :git => 'https://github.com/tozny/e3db-swift'
```

## Author

Tozny

## License

Copyright © Tozny, LLC 2017. All rights reserved.
