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

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        let email = "greg+test9@tozny.com"
//        let dev   = "https://dev.e3db.com/v1/storage"
//        E3db.register(email: email, findByEmail: true, apiUrl: dev) { (result) in
//            switch result {
//            case .success(let config):
//                print("\(config.save(profile: email) ? "Saved" : "Failed to save"): \(config)")
//            case .failure(let err):
//                print("Failed: \(err)")
//            }
//        }

        guard let config = Config(loadProfile: email),
              let e3db = E3db(config: config) else {
            return print("Could not create e3db instance.")
        }

        e3db.getClientInfo() { (result) in
            switch result {
            case .success(let clientInfo):
                print("Got client info! \(clientInfo)")
            case .failure(let error):
                print("Failed to get client info! \(error)")
            }
        }

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

