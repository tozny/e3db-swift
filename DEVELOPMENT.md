
# Development

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



