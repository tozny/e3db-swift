//
//  ViewController.swift
//  E3db
//
//  Created by gstro on 06/25/2017.
//  Copyright (c) 2017 gstro. All rights reserved.
//

import UIKit
import E3db

class ViewController: UIViewController {

    @IBOutlet weak var messageField: UITextField!
    @IBOutlet weak var responseLabel: UILabel!

    let e3db: E3db = E3db(config: TestData.config)
    var latest: String = ""

    @IBAction func write() {
        guard let msg = messageField.text else {
            return print("TextField contains no text")
        }

        let recordData = RecordData(data: ["secret message": msg])
        e3db.write("sdk-test", data: recordData, plain: ["Sent from": "my iPhone"]) { (result) in
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
        e3db.read(recordId: latest) { (result) in
            let text: String
            switch result {
            case .success(let data):
                text = "Record data: \(data)"
            case .failure(let error):
                text = "Failed to read record! \(error)"
            }
            print(text)
            let alert = UIAlertController(title: "Read Record", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

