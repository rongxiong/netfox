//
//  ScenarioRunner.swift
//  netfox_ios_demo
//
//  Fires the URLRequests backing each scenario. All observable state
//  mutations hop to the main queue so SwiftUI can consume them directly.
//

import Foundation

final class ScenarioRunner: NSObject {

    private lazy var session: URLSession = {
        return URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    private let progressLock = NSLock()
    private var progressTasks = [Int: Scenario]()
    private var lastProgressPercent = [Int: Int]()

    // MARK: Single / batch

    func run(_ scenario: Scenario) {
        switch scenario.work {
        case let .single(build, timeout, cancelAfter, tracksProgress):
            runSingle(scenario, build: build, timeout: timeout,
                      cancelAfter: cancelAfter, tracksProgress: tracksProgress)
        case let .batch(build, sequential):
            runBatch(scenario, requests: build(), sequential: sequential)
        }
    }

    func burst(_ requests: [URLRequest]) {
        requests.forEach { request in
            session.dataTask(with: request).resume()
        }
    }

    private func runSingle(_ scenario: Scenario, build: () -> URLRequest,
                           timeout: TimeInterval, cancelAfter: TimeInterval?,
                           tracksProgress: Bool) {
        scenario.task?.cancel()

        var request = build()
        request.timeoutInterval = timeout

        scenario.state = .running

        let task = session.dataTask(with: request) { [weak self] _, response, error in
            self?.finish(scenario: scenario, response: response, error: error)
        }

        scenario.task = task

        if tracksProgress {
            progressLock.lock()
            progressTasks[task.taskIdentifier] = scenario
            progressLock.unlock()
        }

        task.resume()

        if let cancelAfter = cancelAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) { [weak task] in
                task?.cancel()
            }
        }
    }

    private func runBatch(_ scenario: Scenario, requests: [URLRequest], sequential: Bool) {
        scenario.state = .running

        let resultsLock = NSLock()
        var statusCodes = [Int]()
        let group = DispatchGroup()

        func record(response: URLResponse?) {
            resultsLock.lock()
            statusCodes.append((response as? HTTPURLResponse)?.statusCode ?? 0)
            resultsLock.unlock()
        }

        func finishBatch() {
            let okCount = statusCodes.filter { (200..<400).contains($0) }.count
            if okCount == statusCodes.count {
                scenario.state = .success("\(statusCodes.count) × \(statusCodes.first ?? 0)")
            } else {
                scenario.state = .httpError("\(okCount)/\(statusCodes.count) ok")
            }
        }

        if sequential {
            // Recursive chaining with a counter - a DispatchGroup would briefly
            // reach zero between the two hops and notify prematurely.
            var remaining = requests.count
            var iterator = requests.makeIterator()
            func runNext() {
                guard let request = iterator.next() else { return }
                session.dataTask(with: request) { _, response, _ in
                    record(response: response)
                    remaining -= 1
                    DispatchQueue.main.async {
                        if remaining == 0 { finishBatch() } else { runNext() }
                    }
                }.resume()
            }
            runNext()
        } else {
            requests.forEach { request in
                group.enter()
                session.dataTask(with: request) { _, response, _ in
                    record(response: response)
                    group.leave()
                }.resume()
            }
            group.notify(queue: .main, execute: finishBatch)
        }
    }

    private func finish(scenario: Scenario, response: URLResponse?, error: Error?) {
        if let task = scenario.task {
            progressLock.lock()
            progressTasks.removeValue(forKey: task.taskIdentifier)
            lastProgressPercent.removeValue(forKey: task.taskIdentifier)
            progressLock.unlock()
        }

        DispatchQueue.main.async {
            if let error = error as? URLError {
                switch error.code {
                case .cancelled:
                    scenario.state = .cancelled("Cancelled")
                case .timedOut:
                    scenario.state = .transportError("Timeout")
                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                    scenario.state = .transportError("No host")
                case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                     .secureConnectionFailed, .serverCertificateNotYetValid:
                    scenario.state = .transportError("TLS error")
                default:
                    scenario.state = .transportError("Err \(error.code.rawValue)")
                }
                return
            }

            guard let http = response as? HTTPURLResponse else {
                scenario.state = .transportError("No HTTP")
                return
            }

            if (200..<400).contains(http.statusCode) {
                scenario.state = .success("\(http.statusCode)")
            } else {
                scenario.state = .httpError("\(http.statusCode)")
            }
        }
    }
}

extension ScenarioRunner: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        progressLock.lock()
        guard let scenario = progressTasks[dataTask.taskIdentifier] else {
            progressLock.unlock()
            return
        }
        let expected = dataTask.response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown
        let received = dataTask.countOfBytesReceived
        progressLock.unlock()

        guard expected > 0 else { return }

        let percent = Int(Double(received) / Double(expected) * 100)
        progressLock.lock()
        let last = lastProgressPercent[dataTask.taskIdentifier] ?? -1
        guard percent != last else {
            progressLock.unlock()
            return
        }
        lastProgressPercent[dataTask.taskIdentifier] = percent
        progressLock.unlock()

        DispatchQueue.main.async {
            scenario.state = .progress("\(percent)%")
        }
    }
}
