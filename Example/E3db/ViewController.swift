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

    let email = "greg+test18@tozny.com"

    var shouldRegister = true

    @IBAction func write() {
        guard let config = Config(loadProfile: email) else {
            return print("Could not load config for \(email)")
        }

        guard let e3db = E3db(config: config) else {
            return print("Could not create e3db instance.")
        }

        guard let data = messageField.text?.data(using: .utf8) else {
            return print("Could not create data?")
        }

        print(config)

        e3db.write("sdk-test", data: ["secret message": data], plain: ["Sent from": "my iPhone"]) { (result) in
            let text: String
            switch result {
            case .success(let record):
                text = "Wrote record! \(record.meta.recordId!)"
            case .failure(let error):
                text = "Failed to write record! \(error)"
            }
            print(text)
            self.responseLabel.text = text
        }
    }

    func register() {
        let dev = "https://dev.e3db.com/v1/storage"
        E3db.register(email: email, findByEmail: true, apiUrl: dev) { (result) in
            switch result {
            case .success(let config):
                let saved = config.save(profile: self.email)
                print("\(saved ? "Saved" : "Failed to save"): \(config)")
            case .failure(let err):
                print("Failed: \(err)")
            }
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

