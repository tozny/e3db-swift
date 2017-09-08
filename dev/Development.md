## Development

Requires **Xcode Tools**. On macOS, run:

```bash
xcode-select --install
```

If using an Xcode Beta, it may require selecting this Xcode version before
running any of the following commands:

```bash
sudo xcode-select -s <PATH_TO_XCODE_BETA>
```

### Running Integration Tests

If the repo source doesn't include a valid client token, generate one from the
Tozny console. Replace the `TestData` values in `Example/Test/Tests.swift`:

```swift
struct TestData {
    static let apiUrl = ""
    static let token  = ""
}
```

#### Manually Running Tests

All of the building and testing of the SDK can be performed with the Xcode IDE.
If the command line is preferred, instructions are provided below.

First build the SDK (`configuration` can be **Debug** or **Release** depending
on desired logging level -- **Debug** may log sensitive values):

```bash
xcodebuild \
  -workspace "Example/E3db.xcworkspace" \
  -configuration "Release" \
  -scheme "E3db-Example"
```

If a build fails, it may require a clean first:

```bash
xcodebuild clean \
  -workspace "Example/E3db.xcworkspace" \
  -scheme "E3db-Example"
```

A list of supported simulator identifiers is in a file in this directory called
`ios_platform_names_9.0.txt`. To test supported platform simulators and generate
a report, use the scripts included in this directory (requires
[xcpretty](https://github.com/supermarin/xcpretty)):

- Test a single platform (e.g. iPhone 6 Simulator on iOS 9.0):

  ```bash
  xcodebuild test \
    -workspace "Example/E3db.xcworkspace" \
    -configuration "Release" \
    -scheme "E3db-Example" \
    -destination "platform=iOS Simulator,name=iPhone 6,OS=9.0"
  ```

- To test a single platform and generate a report, provide the platform and a
  name for the report, and the results will be in the `testlogs` directory:

  ```bash
  ./test_one_platform 'platform=iOS Simulator,name=iPhone 6,OS=9.0' test-name
  ```

- To test against all supported platform simulators and generate a report, use
  the scripts included in this directory

  ```bash
  ./test_all_platforms ios_platform_names_9.0.txt
  ```

### Generating Docs

Requires [jazzy](https://github.com/realm/jazzy). Run `jazzy` from the repo
root (uses the `.jazzy.yaml` config file):

```bash
jazzy
```

### Linting the SDK

Requires [swiftlint](https://github.com/realm/SwiftLint). Run `swiftlint` from
the repo root (uses the `.swiftlint.yml` config file):

```bash
swiftlint --config $(pwd)/.swiftlint.yml --path E3db/Classes/
```

### Linting the Podspec (for CocoaPods Distribution)

Requires [CocoaPods](http://cocoapods.org). Run the following command
from the repo root:

```bash
pod lib lint
```