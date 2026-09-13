//
//  NFXLocalHTTPServer.swift
//  netfoxTests
//
//  Minimal HTTP server bound to 127.0.0.1 on a port picked by the kernel.
//  It lets the interception tests drive `NFXProtocol` end to end - real
//  sockets, real HTTP - without ever leaving the machine.
//

import Foundation
import Darwin

final class NFXLocalHTTPServer {

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data

        init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        static func json(_ value: [String: Any], status: Int = 200) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
            return Response(status: status, headers: ["Content-Type": "application/json"], body: data)
        }

        static func text(_ string: String, contentType: String = "text/plain", status: Int = 200) -> Response {
            return Response(status: status, headers: ["Content-Type": contentType], body: Data(string.utf8))
        }
    }

    struct RecordedRequest {
        let method: String
        let target: String
        let headers: [String: String]
    }

    enum ServerError: Error, LocalizedError {
        case socket(Int32)
        case bind(Int32)
        case listen(Int32)
        case address(Int32)

        var errorDescription: String? {
            switch self {
            case .socket(let code): return "socket() failed with errno \(code)"
            case .bind(let code): return "bind() failed with errno \(code)"
            case .listen(let code): return "listen() failed with errno \(code)"
            case .address(let code): return "getsockname() failed with errno \(code)"
            }
        }
    }

    private let acceptQueue = DispatchQueue(label: "com.netfox.tests.httpServer.accept")
    private let handlerQueue = DispatchQueue(label: "com.netfox.tests.httpServer.handler")
    private let lock = NSLock()

    private var routes: [String: Response] = [:]
    private var recorded: [RecordedRequest] = []
    private var listenFD: Int32 = -1

    private(set) var port: UInt16 = 0

    var baseURL: URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    deinit {
        stop()
    }

    // MARK: - Configuration

    func register(path: String, response: Response) {
        lock.lock()
        routes[path] = response
        lock.unlock()
    }

    func url(for path: String) -> URL {
        return URL(string: (baseURL?.absoluteString ?? "") + path)!
    }

    // MARK: - Lifecycle

    @discardableResult
    func start() throws -> URL {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw ServerError.socket(errno) }
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
        guard bindResult == 0 else { throw ServerError.bind(errno) }
        guard listen(fd, 16) == 0 else { throw ServerError.listen(errno) }

        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(fd, socketAddress, &length)
            }
        }
        guard nameResult == 0 else { throw ServerError.address(errno) }
        port = UInt16(bigEndian: resolved.sin_port)

        acceptQueue.async { [weak self] in self?.acceptLoop(socket: fd) }
        return baseURL!
    }

    func stop() {
        let fd = listenFD
        listenFD = -1
        port = 0
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
    }

    // MARK: - Recorded traffic

    func recordedRequests() -> [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func resetRecordedRequests() {
        lock.lock()
        recorded = []
        lock.unlock()
    }

    // MARK: - Internals

    private func acceptLoop(socket: Int32) {
        while true {
            let clientFD = accept(socket, nil, nil)
            if clientFD < 0 { return }
            handlerQueue.async { [weak self] in self?.handle(client: clientFD) }
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

            guard let headerEnd = received.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let headerLength = received.distance(from: received.startIndex, to: headerEnd.upperBound)
            let headerText = String(data: received.prefix(headerEnd.lowerBound), encoding: .utf8) ?? ""
            if received.count - headerLength >= Self.contentLength(from: headerText) { break }
            if received.count > 1_048_576 { return }
        }

        guard let text = String(data: received, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first else { return }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0]
        let target = parts[1]
        let path = target.components(separatedBy: "?").first ?? target

        lock.lock()
        let route = routes[path]
        recorded.append(RecordedRequest(method: method, target: target, headers: Self.headers(from: text)))
        lock.unlock()

        guard let route = route else {
            writeResponse(to: fd, status: 404, headers: ["Content-Type": "application/json"], body: Data("{\"error\":\"not found\"}".utf8))
            return
        }
        writeResponse(to: fd, status: route.status, headers: route.headers, body: route.body)
    }

    private func writeResponse(to fd: Int32, status: Int, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
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

    // MARK: - Parsing helpers

    private static func headers(from requestText: String) -> [String: String] {
        var headers: [String: String] = [:]
        let lines = requestText.components(separatedBy: "\r\n").dropFirst()

        for line in lines {
            if line.isEmpty { break }
            guard let separator = line.range(of: ":") else { continue }
            let name = String(line[line.startIndex..<separator.lowerBound])
            let value = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            headers[name.lowercased()] = value
        }
        return headers
    }

    private static func contentLength(from headerText: String) -> Int {
        let headers = self.headers(from: headerText + "\r\n\r\n")
        return Int(headers["content-length"] ?? "") ?? 0
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Status \(status)"
        }
    }
}
