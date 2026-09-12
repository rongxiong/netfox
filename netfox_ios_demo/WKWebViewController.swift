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

    private var webView: WKWebView!

    init() {
        super.init(nibName: nil, bundle: nil)
        let image = UIImage(systemName: "safari")
        tabBarItem = UITabBarItem(title: "WKWebView", image: image, selectedImage: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .tertiarySystemBackground

        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        // Distinctive gray background for the demo surface.
        webView.backgroundColor = UIColor(red: 0.36, green: 0.39, blue: 0.40, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        webView.load(URLRequest(url: URL(string: "https://github.com/rongxiong/netfox")!))
    }
}
