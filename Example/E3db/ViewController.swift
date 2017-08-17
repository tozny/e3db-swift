//
//  ViewController.swift
//  E3db
//

import UIKit
import E3db

struct DataTest: RecordData {
    let data: [String: String]
}

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

        let recordData = DataTest(data: ["secret message": msg])
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
        guard latest.count > 0 else {
            return print("No records written this session")
        }
        e3db?.read(recordId: latest) { (result: E3dbResult<DataTest>) in
            let text: String
            switch result {
            case .success(let record):
                text = "Record data: \(record.data)"
            case .failure(let error):
                text = "Failed to read record! \(error)"
            }
            print(text)
            let alert = UIAlertController(title: "Read Record", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default))
            self.present(alert, animated: true)
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

