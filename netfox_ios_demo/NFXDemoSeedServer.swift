//
//  NFXDemoSeedServer.swift
//  netfox_ios_demo
//
//  A tiny HTTP server bound to 127.0.0.1, started only when the UI tests ask
//  for the seeded batch (`-nfxUITestSeed`).
//
//  netfox intercepts the seeded requests and re-issues them from its own
//  internal session, so the answers cannot come from a custom URLProtocol -
//  the internal session carries its own protocol list. A real socket on the
//  loopback interface always answers it, and gives the tests real status
//  codes and bodies without touching the internet.
//

import Foundation
import Darwin

final class NFXDemoSeedServer {

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data

        init(status: Int, contentType: String, body: Data) {
            self.status = status
            self.headers = ["Content-Type": contentType]
            self.body = body
        }

        static func json(_ value: [String: Any], status: Int = 200) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
            return Response(status: status, contentType: "application/json", body: data)
        }

        static func text(_ value: String, contentType: String, status: Int = 200) -> Response {
            return Response(status: status, contentType: contentType, body: Data(value.utf8))
        }
    }

    private let queue = DispatchQueue(label: "com.netfox.demo.seedServer")
    private let lock = NSLock()

    private var routes: [String: Response] = [:]
    private var listenFD: Int32 = -1

    private(set) var port: UInt16 = 0

    var baseURL: URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    deinit {
        stop()
    }

    func start(routes: [String: Response]) throws {
        self.routes = routes

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return }
        listenFD = fd

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var noSignalPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignalPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return }
        guard listen(fd, 16) == 0 else { return }

        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(fd, socketAddress, &length)
            }
        }
        guard nameResult == 0 else { return }
        port = UInt16(bigEndian: resolved.sin_port)

        queue.async { [weak self] in self?.acceptLoop(socket: fd) }
    }

    func stop() {
        let fd = listenFD
        listenFD = -1
        port = 0
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
    }

    // MARK: - Internals

    private func acceptLoop(socket: Int32) {
        while true {
            let clientFD = accept(socket, nil, nil)
            if clientFD < 0 { return }
            handle(client: clientFD)
        }
    }

    private func handle(client fd: Int32) {
        defer { close(fd) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        var received = Data()

        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { return }
            received.append(buffer, count: count)
            if received.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            if received.count > 1_048_576 { return }
        }

        guard let text = String(data: received, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first else { return }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let target = parts[1]
        let path = target.components(separatedBy: "?").first ?? target

        lock.lock()
        let response = routes[path]
        lock.unlock()

        guard let response = response else {
            write(to: fd, status: 404, headers: ["Content-Type": "application/json"], body: Data("{\"error\":\"not found\"}".utf8))
            return
        }
        write(to: fd, status: response.status, headers: response.headers, body: response.body)
    }

    private func write(to fd: Int32, status: Int, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(body)

        payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < payload.count {
                let written = send(fd, base.advanced(by: sent), payload.count - sent, Int32(0))
                if written <= 0 { break }
                sent += written
            }
        }
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Status \(status)"
        }
    }
}
