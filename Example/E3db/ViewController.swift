//
//  ViewController.swift
//  E3db
//

import UIKit
import E3db

class ViewController: UIViewController {

    @IBOutlet weak var messageField: UITextField!
    @IBOutlet weak var responseLabel: UILabel!

//    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
//        return 1
//    }
//
//    var lastIndex: Int = 0
//
//    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
//        if records.count >= indexPath.row {
//            let q = QueryParams(includeData: false, contentTypes: ["example"], afterIndex:lastIndex)
//            e3db.query(q) { (result) in
//                switch result {
//                case .success(let records):
//                    records.forEach { print("Record: \($0)") }
//                    self.records += records
//                case .failure(let err):
//                    print("Error: \(err)")
//                }
//            }
//        }
//
//        return UITableViewCell()
//    }

    lazy var e3db: Client? = {
        // load config from secure enclave
        guard let config = Config() else { return nil }
        return Client(config: config)
    }()

    var latest: UUID?

    @IBAction func write() {
        guard let msg = messageField.text else {
            return print("TextField contains no text")
        }

        let recordData = RecordData(clearText: ["secret message": msg])
        e3db?.write(type: "sdk-test-2", data: recordData, plain: ["Sent from": "my iPhone"]) { (result) in
            let text: String
            switch result {
            case .success(let record):
                self.latest = record.meta.recordId
                text = "Wrote record! \(record.meta.recordId)"
            case .failure(let error):
                text = "Failed to write record! \(error)"
            }
            print(text)
            self.responseLabel.text = text
        }
    }

//    let tableView: UITableView = {
//        let tableView = UITableView()
//        tableView.dataSource =
//        return tableView
//    }()

//    // TableView UI Element set from Story Board
//    @IBOutlet var tableView: UITableView!
//
//    // TableViewDataSource
//    var records: [Record] = [] {
//        didSet {
//            DispatchQueue.main.async {
//                self.tableView.reloadData()
//            }
//        }
//    }

    @IBAction func read() {
//        let q = QueryParams(includeData: true, contentTypes: ["example"])
//        e3db.query(q) { (result) in
//            switch result {
//            case .success(let records):
//                records.forEach { print("Record: \($0)") }
//                self.records = records
//            case .failure(let err):
//                print("Error: \(err)")
//            }
//        }
//        let q = QueryParams(count: 2, includeData: true)
//        var recs = [Record]()
//        e3db?.queryB(params: q, onRecord: { (r) in
//            print("Record!")
//            recs.append(r)
//        }, done: { (err) in
//            if let e = err {
//                print("error: \(e)")
//            }
//            print("Done! Records: \n\(recs)")
//        })
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // save test config under default profile name, protects it in secure enclave w/ TouchID
        guard TestData.config.save() else { return print("Could not save config") }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

