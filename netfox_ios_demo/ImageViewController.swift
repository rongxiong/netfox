//
//  ImageViewController.swift
//  netfox_ios_demo
//
//  Created by Nathan Jangula on 10/12/17.
//  Copyright © 2017 kasketis. All rights reserved.
//

import UIKit

class ImageViewController: UIViewController {

    private let imageView = UIImageView()
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    init() {
        super.init(nibName: nil, bundle: nil)
        let image = UIImage(systemName: "photo")
        tabBarItem = UITabBarItem(title: "Image", image: image, selectedImage: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .tertiarySystemBackground

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        let loadButton = UIButton(type: .system)
        loadButton.setTitle("Load random image", for: .normal)
        loadButton.addTarget(self, action: #selector(tappedLoadImage), for: .touchUpInside)
        loadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            loadButton.topAnchor.constraint(equalTo: imageView.bottomAnchor),
            loadButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            loadButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            loadButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            loadButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func tappedLoadImage() {
        dataTask?.cancel()

        if session == nil {
            session = URLSession(configuration: URLSessionConfiguration.default)
        }

        if let url = URL(string: "https://picsum.photos/\(Int(imageView.frame.size.width))/\(Int(imageView.frame.size.height))") {
            dataTask = session?.dataTask(with: url, completionHandler: { (data, response, error) in
                if let error = error {
                    self.handleCompletion(error: error.localizedDescription, data: data)
                } else {
                    guard let data = data else { self.handleCompletion(error: "Invalid data", data: nil); return }
                    guard let response = response as? HTTPURLResponse else { self.handleCompletion(error: "Invalid response", data: data); return }
                    guard response.statusCode >= 200 && response.statusCode < 300 else { self.handleCompletion(error: "Invalid response code", data: data); return }

                    self.handleCompletion(error: error?.localizedDescription, data: data)
                }
            })

            dataTask?.resume()
        }
    }

    private func handleCompletion(error: String?, data: Data?) {
        DispatchQueue.main.async {

            if let error = error {
                NSLog(error)
                return
            }

            if let data = data {
                let image = UIImage(data: data)
                NSLog("\(image?.size.width ?? 0),\(image?.size.height ?? 0)")
                self.imageView.image = image
            }
        }
    }
}
