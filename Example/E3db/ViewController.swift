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

    @IBAction func write() {
        guard let msg = messageField.text else {
            return print("TextField contains no text")
        }

        let recordData = RecordData(data: ["secret message": msg])
        e3db.write("sdk-test", data: recordData, plain: ["Sent from": "my iPhone"]) { (result) in
            let text: String
            switch result {
            case .success(let record):
                text = "Wrote record! \(record.meta.recordId)"
            case .failure(let error):
                text = "Failed to write record! \(error)"
            }
            print(text)
            self.responseLabel.text = text
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

