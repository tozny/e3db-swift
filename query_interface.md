## Options for E3db Swift SDK Query Interface

Constraints and use-cases specific to mobile:
- Networking is relatively unreliable so responses could take awhile
- Long-running tasks should be backgrounded so main UI thread is not blocked
- Calls to network should be minimized to preserve battery
- Typical use-case for listing records would use a `UITableView`

An example implementation of the table view is below for context of comparison.
An array of E3db `Record` objects acts as the table's data source. The table
view is refreshed on the main thread whenever the records array (table view data
source) is updated.

```swift
// TableView UI Element
var tableView: UITableView

// TableViewDataSource
var records: [Record] = [] {
    didSet {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
}
```

This document is to help decide on the best approach for the MVP. Another model,
likely a notification / subscription based approach, may supersede this decision
in future iterations of the SDK.

### Option 1: All results at once

This method most closely resembles the other `E3db` methods where it supplies
a `Result<A, E3dbError>` in a single "completion" callback.

This approach's callback is only called once the implementation completes the
necessary paging and the full result set is collected into memory.

```swift
let q = QueryParams(includeData: false, contentTypes: ["example"])
e3db.query(q) { (result) in
    switch result {
    case .success(let records):
        records.forEach { print("Record: \($0)") }
        self.records = records
    case .failure(let err):
        print("Error: \(err)")
    }
}
```

Examples:
- [Twitter](https://dev.twitter.com/twitterkit/ios/access-rest-api)
- [Box](https://github.com/box/box-ios-sdk/blob/master/doc/Files.md)
- [CloudMine](https://cloudmine.io/docs/#/ios)

### Option 2: Callback for each record and for done

This method provides two callbacks, one for when a single `Record` is available,
and another to signal completion or if an error occurred. This method simulates
a streaming interface, though the underlying implementation is paged.

This approach collects, at most, a page of records into memory at a time. The
implementation hides the paging itself, like Option 1, and will still process
the full result set.

```swift
let q = QueryParams(includeData: false, contentTypes: ["example"])
e3db.query(q, onRecord: { (record) in
    print("Record: \(record)")
    self.records += record
}, done: { (error?) in
    if let err = error {
        print("Error: \(err)")
    }
    // Could choose to delay UI update until here
})
```

### Option 3: Callback for page at a time

This method provides a single callback of `Result<A, E3dbError>` much
like Option 1 and the other `E3db` methods, but the record array is only a
single page.

Like Option 2, it only collects one page of records into memory at a time. But
unlike either of the previous Options, it does not process the full result set.
Instead, the caller is responsible for paging themselves. This requires a new
data type to expose the paging details, e.g. a named tuple
`Result<(records: [Record], lastIndex: Int), E3dbError>`, or a full data
structure:
```swift
struct QueryResponse {
    let records: [Record]
    let lastIndex: Int
}
```
which would be provided to the callback, i.e. `Result<QueryResponse, E3dbError>`

This allows a lazy-loading approach where subsets of records can be presented on
screen as needed, and should the user scroll beyond the available records,
another call can be made to fetch the next page.

```swift
// Caller keeps track of index
var lastIndex: Int = 0

func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.row >= records.count {
        let q = QueryParams(includeData: false, contentTypes: ["example"], afterIndex:lastIndex)
        e3db.query(q) { (result) in
            switch result {
            case .success(let response):
                records.forEach { print("Record: \($0)") }
                self.lastIndex = response.lastIndex   // keep track of paging
                self.records += response.records
            case .failure(let err):
                print("Error: \(err)")
            }
        }
    }
    // Setup UITableViewCell ...
    return cell
}
```

Examples:
- [Dropbox](http://dropbox.github.io/dropbox-sdk-obj-c/api-docs/latest/Classes/DBFILESUserAuthRoutes.html#/c:objc(cs)DBFILESUserAuthRoutes(im)listFolderContinue:)
- [Spotify](https://spotify.github.io/ios-sdk/Classes/SPTPlaylistList.html#//api/name/playlistsForUser:withAccessToken:callback:)
- [MediaFire](https://github.com/MediaFire/mediafire-objectivec-sdk/blob/9fcd1e5ea6a8d0ac5a7242bd7502cb14e4fb7480/MediaFireSDKDemos/MFSDK%20iOS%20Demo/MFSDK%20Demo/MFContentsViewController.m#L51)
