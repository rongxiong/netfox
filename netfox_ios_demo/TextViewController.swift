//
//  TextViewController.swift
//  netfox_ios_demo
//
//  Created by Nathan Jangula on 10/12/17.
//  Copyright © 2017 kasketis. All rights reserved.
//

import UIKit

class TextViewController: UIViewController {

    private let textView = UITextView()
    private var session: URLSession!
    private var dataTask: URLSessionDataTask?

    init() {
        super.init(nibName: nil, bundle: nil)
        let image = UIImage(systemName: "doc.text")
        tabBarItem = UITabBarItem(title: "Text", image: image, selectedImage: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .tertiarySystemBackground

        textView.font = .systemFont(ofSize: 14)
        textView.backgroundColor = .tertiarySystemBackground
        textView.isEditable = false
        textView.isSelectable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        let loadButton = UIButton(type: .system)
        loadButton.setTitle("Tell me a joke", for: .normal)
        loadButton.addTarget(self, action: #selector(tappedLoad), for: .touchUpInside)
        loadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadButton)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            loadButton.topAnchor.constraint(equalTo: textView.bottomAnchor),
            loadButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            loadButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            loadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            loadButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func tappedLoad() {
        dataTask?.cancel()

        if session == nil {
            session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
        }

        guard let url = URL(string: "https://api.chucknorris.io/jokes/random") else { return }
        let request = URLRequest(url: url)
        dataTask = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                self.handleCompletion(error: error.localizedDescription, data: data)
            } else {
                guard let data = data else { self.handleCompletion(error: "Invalid data", data: nil); return }
                guard let response = response as? HTTPURLResponse else { self.handleCompletion(error: "Invalid response", data: data); return }
                guard response.statusCode >= 200 && response.statusCode < 300 else { self.handleCompletion(error: "Invalid response code", data: data); return }

                self.handleCompletion(error: error?.localizedDescription, data: data)
            }
        }

        dataTask?.resume()
    }

    private func handleCompletion(error: String?, data: Data?) {
        DispatchQueue.main.async {

            if let error = error {
                NSLog(error)
                return
            }

            if let data = data {
                do {
                    let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String : Any]

                    if let message = dict?["value"] as? String {
                        self.textView.text = message
                    }
                } catch {

                }
            }
        }
    }
}

extension TextViewController : URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(URLSession.AuthChallengeDisposition.useCredential, nil)
    }
}
