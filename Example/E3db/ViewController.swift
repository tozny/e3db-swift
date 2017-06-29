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
        let email = "greg+test7@tozny.com"
//        Client.register(email: email, findByEmail: false) { (res) in
//            switch res {
//            case let .success(config):
//                if config.save(profileName: email) {
//                    print("Saved: \(config)")
//                } else {
//                    print("Failed to save: \(config)")
//                }
//
//            case let .failure(err):
//                print("Failed: \(err)")
//            }
//        }

        if let loaded = Config(loadProfile: email) {
            print("Loaded: \(loaded)")
        } else {
            print("Failed to load :(")
        }
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

