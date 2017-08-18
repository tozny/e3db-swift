//
//  ViewController.swift
//  E3db
//

import UIKit
import E3db

class ViewController: UIViewController {

    @IBOutlet weak var messageField: UITextField!
    @IBOutlet weak var responseLabel: UILabel!

    lazy var e3db: E3db? = {
        // load config from secure enclave
        guard let config = Config() else { return nil }
        return E3db(config: config)
    }()

    var latest: String = ""

    @IBAction func write() {
        guard let msg = messageField.text else {
            return print("TextField contains no text")
        }

        let recordData = RecordData(data: ["secret message": msg])
        e3db?.write("sdk-test-2", data: recordData, plain: ["Sent from": "my iPhone"]) { (result) in
            let text: String
            switch result {
            case .success(let record):
                self.latest = record.meta.recordId
                text = "Wrote record! \(self.latest)"
            case .failure(let error):
                text = "Failed to write record! \(error)"
            }
            print(text)
            self.responseLabel.text = text
        }
    }

    @IBAction func read() {
        let q = Query(count: 2, includeData: true)
        e3db?.search(query: q) { (result) in
            result.map { $0.forEach { print("\($0)") } }
        }
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

