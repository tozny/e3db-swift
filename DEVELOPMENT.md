
# Development

## Building

The `e3db-swift` repository uses two package managers: [Carthage](https://formulae.brew.sh/formula/carthage#default) for `E3db` and [Cocoapods](https://cocoapods.org/) for `Example`. Follow the links above to install both tools, then follow the steps below to build the projects' dependencies:

1. Run the `carthage update --use-xcframeworks --platform iOS` command from the root of the directory which contains the `Cartfile`. This will build dependencies for the `E3db` target.  

2. (Optional) If you previously installed dependencies you may need to migrate to using XCFrameworks. Follow the steps [here](https://github.com/Carthage/Carthage#migrating-a-project-from-framework-bundles-to-xcframeworks) in order to complete the migration step, if necessary.

3. **Note that this step may not be necessary, but it is worth checking to see if the XCFramework are linked in Xcode before continuing**. Follow step 6 in the [Carthage Quick Start](https://github.com/Carthage/Carthage#quick-start) guide to move the XCFrameworks bundles into the project in Xcode. Below are two images showing where the XCFrameworks should be moved from the Finder to Xcode: 

    Drag the `.xcframework` bundles from Finder
    ![Finder menu showing XCFramework Bundles](./documentation/images/xcframeworks-finder-loc.png)    

    To the `Link Binaries With Libraries` section of the `E3db` target's Build Phases. Open `E3db.xcodeproj` in Xcode to view this menu:
    ![Xcode Build Phases Menu](./documentation/images/xcframeworks-xcode-loc.png)


4. Run `pod install` from the `Example/` directory to install necessary dependencies for the `E3db-Example` target. 

5. The `E3db-example` target can now be opened in Xcode by opening the `E3db-example.xcworkspace` in `Example/` directory, and the `E3db` target can be opened by opening `E3db.xcodeproj` in the root of the repository. 

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
