
# Development

## Testing

### Configuration

Before running the tests you will want to add configuration for a valid Tozny endpoint to test against (e.g. Tozny Platform running locally [exposed over the internet with ngrok](https://ngrok.com), or the Tozny Development, Staging, or Production SaaS environments).

Specifically, to run the `IntegrationTests.swift` [tests](./Example/IntegrationTests.swfit) (covering TozStore APIs for reading, writing, sharing, searching, and deleting encrypted records) you will need to add a value for `apiUrl` and `token` for a Tozny environment to test against and a valid registration token for that environment.

```swift
    static let apiUrl: String? = "http://51a0fe63a6b4.ngrok.io/"
    static let token  = "41a0041e6685d0f49e95235e68ac6180b441e3fbefaef7357ebc29b050976d12"
```

**Note: Currently all the tests in the above file related to working with Files fail**

To run the [integration tests covering TozID APIs](./Example/IdentityTests.swfit) for registering and logging in Identities, and TozStore features such as reading and writing notes you will need to add values for a valid Identity, a TozID login Application for a realm, and a registration token

```swift
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
        self.regToken = "41a0041e6685d0f49e95235e68ac6180b441e3fbefaef7357ebc29b050976d12"
        self.validApplication = Application.init(apiUrl: "http://4d487b296be0.ngrok.io", appName: "account", realmName: "local", brokerTargetUrl: "http://id.tozny.com/local/recover")
    }

	// ...rest of class omitted
}
```

**Note: Currently all the tests in the above file that call an API fail**


## Example App

### Configuration

Before running the Example app you will want to add configuration for a valid Tozny Client registration token for the [Tozny Production environment](https://dashboard.tozny.com) in the [entry point for the app](./Example/E3db-Example/ViewController.swift)

```swift
// Create an account and generate
// a client token from https://dashboard.tozny.com
private let e3dbToken = "259918a1804c89f4acd10b134810442284e4b2d93776c5a7a1c8934e14113a81"
```


## Release 

To release a new version make sure that all added files are within the pod defined source folders

From E3db.podspec
```
s.version          = '4.1.0-alpha.1' // edit this version to match the eventual release

s.source_files = 'E3db/Classes/**/*'
```

Verify that the pod can be compiled with
```
pod lib lint
```

tag the release and push the tags to github
```
git tag '4.1.0-alpha.1'
git push --tags
```

under repo > releases > select `Draft a new release` for the tag you're pushing.
