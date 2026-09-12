//
//  WebViewController.swift
//  netfox_ios_demo
//
//  Created by Nathan Jangula on 10/12/17.
//  Copyright © 2017 kasketis. All rights reserved.
//

import UIKit

class WebViewController: UIViewController {
    
    @IBOutlet weak var webView: UIWebView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // iOS 26 compatibility mode ignores images assigned to the
        // storyboard-archived UITabBarItem; use a code-created item.
        let image = UIImage(systemName: "globe")
        tabBarItem = UITabBarItem(title: tabBarItem.title, image: image, selectedImage: image)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.loadRequest(URLRequest(url: URL(string: "https://github.com/rongxiong/netfox")!))
    }
}
