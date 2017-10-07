//
//  HostClientPickerViewController.swift
//  WorkspaceAR
//
//  Created by Avery Lamp on 10/7/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import UIKit

class HostClientPickerViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        let blurEffect = UIBlurEffect(style: UIBlurEffectStyle.light)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.layer.cornerRadius = 20
        blurEffectView.clipsToBounds = true
        blurEffectView.frame = self.view.bounds
        
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(blurEffectView, at: 0)
        ConnectivityManager.shared().delegate = self
        // Do any additional setup after loading the view.
    }

    @IBAction func hostButtonClicked(_ sender: Any) {
        DataManager.shared().userType = .Host
        print("Host Picked")
        
        ConnectivityManager.shared().startAdvertising()
        
        NotificationCenter.default.post(name: hidePromptNotificationName, object: self)
        
        
    }
    
    @IBAction func clientButtonClicked(_ sender: Any) {
        print("Client Picked")
        DataManager.shared().userType = .Client
        
        ConnectivityManager.shared().startBrowsing()
        
        NotificationCenter.default.post(name: hidePromptNotificationName, object: self)
    }
    
}


extension HostClientPickerViewController:ConnectivityManagerDelegate {
    func connectedDevicesChanged(manager: ConnectivityManager, connectedDevices: [String]) {
        print("--- Connected Devices Changed ---")
        print("New Devices: \(connectedDevices)")
    }
    
    func dataReceived(manager: ConnectivityManager, data: Data) {
        print("Received Data" )
    }
    
    
}
