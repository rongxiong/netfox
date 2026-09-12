//
//  WKWebViewController.swift
//  netfox_ios_demo
//
//  Created by Nathan Jangula on 9/14/18.
//  Copyright © 2017 kasketis. All rights reserved.
//

import UIKit
import WebKit

class WKWebViewController: UIViewController {
    
    @IBOutlet weak var webView: WKWebView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // iOS 26 compatibility mode ignores images assigned to the
        // storyboard-archived UITabBarItem; use a code-created item.
        let image = UIImage(systemName: "safari")
        tabBarItem = UITabBarItem(title: tabBarItem.title, image: image, selectedImage: image)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: URL(string: "https://github.com/rongxiong/netfox")!))
    }
}
