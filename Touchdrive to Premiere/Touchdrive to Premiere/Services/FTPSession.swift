import Foundation
import Network
import OSLog

// MARK: - FTP Session

final class FTPSession {
    let id = UUID()

    var onClose: ((UUID) -> Void)?
    var onTransferComplete: ((FTPTransferStatus) -> Void)?

    // MARK: - Private State

    private let connection: NWConnection
    private weak var server: FTPServer?

    private var isAuthenticated = false
    private var pendingUsername: String?

    private var currentDirectory: String = "/"
    private var transferType: String = "A" // A=ASCII, I=Binary
    private var dataBuffer = Data()

    // PASV data channel
    private var dataListener: NWListener?
    private var dataConnection: NWConnection?

    // Active file transfer
    private var activeTransfer: FTPTransferStatus?
    private var fileHandle: FileHandle?
    private var transferDestination: URL?

    private let ioQueue = DispatchQueue(label: "com.northwoods.ftp.io", qos: .utility)

    // MARK: - Init

    init(connection: NWConnection, server: FTPServer) {
        self.connection = connection
        self.server = server
    }

    // MARK: - Lifecycle

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.ftp.debug("FTP control connection ready")
                self.send("220 Synaxis FTP Server Ready\r\n")
                self.receiveLoop()
            case .failed(let error):
                Log.ftp.error("FTP control connection failed: \(error.localizedDescription)")
                self.cleanUp()
            case .cancelled:
                self.cleanUp()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    func close() {
        connection.cancel()
        cleanUp()
    }

    private func cleanUp() {
        fileHandle?.closeFile()
        fileHandle = nil
        dataConnection?.cancel()
        dataConnection = nil
        dataListener?.cancel()
        dataListener = nil
        onClose?(id)
    }

    // MARK: - Send

    private func send(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                Log.ftp.error("FTP send error: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                Log.ftp.error("FTP receive error: \(error.localizedDescription)")
                self.close()
                return
            }

            if let data {
                self.dataBuffer.append(data)
                self.processCommands()
            }

            if isComplete {
                Log.ftp.info("FTP control connection closed by client")
                self.cleanUp()
            } else {
                self.receiveLoop()
            }
        }
    }

    // MARK: - Command Processing

    private func processCommands() {
        while let range = dataBuffer.range(of: Data("\r\n".utf8)) {
            let lineData = dataBuffer[dataBuffer.startIndex..<range.lowerBound]
            dataBuffer.removeSubrange(dataBuffer.startIndex...range.upperBound - 1)

            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) else {
                continue
            }

            if line.isEmpty { continue }

            let parts = line.split(separator: " ", maxSplits: 1)
            let command = String(parts[0]).uppercased()
            let argument = parts.count > 1 ? String(parts[1]) : nil

            // Log command (mask PASS)
            if command == "PASS" {
                Log.ftp.debug("FTP < PASS ****")
            } else {
                Log.ftp.debug("FTP < \(line)")
            }

            handleCommand(command, argument: argument)
        }
    }

    // MARK: - Command Handler

    private func handleCommand(_ command: String, argument: String?) {
        switch command {
        case "USER":
            handleUSER(argument)
        case "PASS":
            handlePASS(argument)
        case "SYST":
            send("215 UNIX Type: L8\r\n")
        case "FEAT":
            send("211-Features:\r\n UTF8\r\n PASV\r\n SIZE\r\n211 End\r\n")
        case "OPTS":
            if argument?.uppercased().hasPrefix("UTF8") == true {
                send("200 UTF8 mode enabled\r\n")
            } else {
                send("502 Option not implemented\r\n")
            }
        case "TYPE":
            handleTYPE(argument)
        case "PWD", "XPWD":
            send("257 \"\(currentDirectory)\" is current directory\r\n")
        case "CWD", "XCWD":
            handleCWD(argument)
        case "CDUP", "XCUP":
            handleCWD("..")
        case "MKD", "XMKD":
            handleMKD(argument)
        case "PASV":
            handlePASV()
        case "STOR":
            handleSTOR(argument)
        case "LIST", "NLST":
            handleLIST()
        case "SIZE":
            handleSIZE(argument)
        case "QUIT":
            send("221 Goodbye\r\n")
            close()
        case "NOOP":
            send("200 OK\r\n")
        case "PORT":
            // Active mode not supported; Canon C200 uses PASV
            send("502 PORT not supported, use PASV\r\n")
        case "EPSV":
            handleEPSV()
        default:
            Log.ftp.warning("FTP unknown command: \(command)")
            send("502 \(command) not implemented\r\n")
        }
    }

    // MARK: - AUTH

    private func handleUSER(_ username: String?) {
        guard let username, !username.isEmpty else {
            send("501 Syntax error: username required\r\n")
            return
        }
        pendingUsername = username
        send("331 Password required for \(username)\r\n")
    }

    private func handlePASS(_ password: String?) {
        guard let username = pendingUsername else {
            send("503 Login with USER first\r\n")
            return
        }
        guard let password, !password.isEmpty else {
            send("501 Syntax error: password required\r\n")
            return
        }

        guard let server, username == server.username, password == server.password else {
            Log.ftp.warning("FTP login failed for user: \(username)")
            pendingUsername = nil
            send("530 Login incorrect\r\n")
            return
        }

        isAuthenticated = true
        pendingUsername = nil
        Log.ftp.info("FTP login success: \(username)")
        send("230 User \(username) logged in\r\n")
    }

    private func requireAuth() -> Bool {
        guard isAuthenticated else {
            send("530 Not logged in\r\n")
            return false
        }
        return true
    }

    // MARK: - TYPE

    private func handleTYPE(_ argument: String?) {
        guard let arg = argument?.uppercased() else {
            send("501 Syntax error\r\n")
            return
        }
        if arg.hasPrefix("A") {
            transferType = "A"
            send("200 Type set to A\r\n")
        } else if arg.hasPrefix("I") || arg.hasPrefix("L") {
            transferType = "I"
            send("200 Type set to I\r\n")
        } else {
            send("504 Type not supported\r\n")
        }
    }

    // MARK: - CWD

    private func handleCWD(_ path: String?) {
        guard requireAuth() else { return }
        guard let path else {
            send("501 Syntax error: path required\r\n")
            return
        }

        if path == ".." {
            let parent = (currentDirectory as NSString).deletingLastPathComponent
            currentDirectory = parent.isEmpty ? "/" : parent
        } else if path.hasPrefix("/") {
            currentDirectory = path
        } else {
            currentDirectory = (currentDirectory as NSString).appendingPathComponent(path)
        }

        send("250 Directory changed to \(currentDirectory)\r\n")
    }

    // MARK: - MKD

    private func handleMKD(_ path: String?) {
        guard requireAuth() else { return }
        guard let path else {
            send("501 Syntax error: path required\r\n")
            return
        }

        let fullPath: String
        if path.hasPrefix("/") {
            fullPath = path
        } else {
            fullPath = (currentDirectory as NSString).appendingPathComponent(path)
        }

        send("257 \"\(fullPath)\" directory created\r\n")
    }

    // MARK: - PASV

    private func handlePASV() {
        guard requireAuth() else { return }

        // Clean up any previous data channel
        dataConnection?.cancel()
        dataConnection = nil
        dataListener?.cancel()
        dataListener = nil

        do {
            // Listen on ephemeral port (port 0) with IPv4 support
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: .any)

            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                self.dataConnection?.cancel()
                self.dataConnection = conn
                conn.start(queue: .main)
                Log.ftp.debug("FTP data connection accepted")
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        self.send("425 Cannot open data connection\r\n")
                        return
                    }

                    let ip = self.localIPAddress()
                    let ipParts = ip.split(separator: ".").map(String.init)
                    guard ipParts.count == 4 else {
                        self.send("425 Cannot determine local address\r\n")
                        return
                    }

                    let p1 = port / 256
                    let p2 = port % 256
                    let response = "227 Entering Passive Mode (\(ipParts[0]),\(ipParts[1]),\(ipParts[2]),\(ipParts[3]),\(p1),\(p2))\r\n"
                    Log.ftp.debug("FTP PASV: port \(port)")
                    self.send(response)

                case .failed(let error):
                    Log.ftp.error("FTP PASV listener failed: \(error.localizedDescription)")
                    self.send("425 Cannot open data connection\r\n")

                default:
                    break
                }
            }

            listener.start(queue: .main)
            dataListener = listener

        } catch {
            Log.ftp.error("FTP PASV failed: \(error.localizedDescription)")
            send("425 Cannot open data connection\r\n")
        }
    }

    // MARK: - EPSV

    private func handleEPSV() {
        guard requireAuth() else { return }

        dataConnection?.cancel()
        dataConnection = nil
        dataListener?.cancel()
        dataListener = nil

        do {
            let listener = try NWListener(using: .tcp, on: .any)

            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                self.dataConnection?.cancel()
                self.dataConnection = conn
                conn.start(queue: .main)
                Log.ftp.debug("FTP EPSV data connection accepted")
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        self.send("425 Cannot open data connection\r\n")
                        return
                    }
                    let response = "229 Entering Extended Passive Mode (|||\(port)|)\r\n"
                    Log.ftp.debug("FTP EPSV: port \(port)")
                    self.send(response)
                case .failed(let error):
                    Log.ftp.error("FTP EPSV listener failed: \(error.localizedDescription)")
                    self.send("425 Cannot open data connection\r\n")
                default:
                    break
                }
            }

            listener.start(queue: .main)
            dataListener = listener

        } catch {
            Log.ftp.error("FTP EPSV failed: \(error.localizedDescription)")
            send("425 Cannot open data connection\r\n")
        }
    }

    // MARK: - LIST

    private func handleLIST() {
        guard requireAuth() else { return }

        // Wait briefly for data connection to be established
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let dataConn = self.dataConnection else {
                self?.send("425 No data connection\r\n")
                return
            }

            self.send("150 Opening data connection for directory listing\r\n")

            // Send empty listing (camera only uploads, doesn't need to browse)
            let listing = "total 0\r\n"
            let data = Data(listing.utf8)
            dataConn.send(content: data, isComplete: true, completion: .contentProcessed { [weak self] error in
                if let error {
                    Log.ftp.error("FTP LIST send error: \(error.localizedDescription)")
                }
                self?.closeDataConnection()
                self?.send("226 Transfer complete\r\n")
            })
        }
    }

    // MARK: - SIZE

    private func handleSIZE(_ path: String?) {
        guard requireAuth() else { return }
        // File size queries — report 0 since files don't exist on server yet
        send("550 File not found\r\n")
    }

    // MARK: - STOR (File Upload)

    private func handleSTOR(_ filename: String?) {
        guard requireAuth() else { return }
        guard let filename, !filename.isEmpty else {
            send("501 Syntax error: filename required\r\n")
            return
        }

        guard let destDir = server?.resolveTransferPath() else {
            Log.ftp.error("FTP STOR: no base path configured")
            send("550 No transfer destination configured\r\n")
            return
        }

        // Start accessing security-scoped resource if available
        _ = server?.basePathURL?.startAccessingSecurityScopedResource()

        // Create directory structure
        let cleanFilename = (filename as NSString).lastPathComponent
        let destFile = destDir.appendingPathComponent(cleanFilename)

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            Log.ftp.error("FTP STOR mkdir failed: \(error.localizedDescription)")
            send("550 Cannot create directory: \(error.localizedDescription)\r\n")
            return
        }

        // Create the file
        FileManager.default.createFile(atPath: destFile.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: destFile.path) else {
            Log.ftp.error("FTP STOR cannot open file: \(destFile.path)")
            send("550 Cannot create file\r\n")
            return
        }

        fileHandle = handle
        transferDestination = destFile
        activeTransfer = FTPTransferStatus(fileName: cleanFilename)

        Log.ftp.info("FTP STOR: \(cleanFilename) → \(destDir.path)")

        // Wait for data connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let dataConn = self.dataConnection else {
                self?.send("425 No data connection\r\n")
                self?.fileHandle?.closeFile()
                self?.fileHandle = nil
                return
            }

            self.send("150 Opening data connection for \(cleanFilename)\r\n")
            self.receiveFileData(on: dataConn)
        }
    }

    private func receiveFileData(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1048576) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.ioQueue.async { [weak self] in
                    self?.fileHandle?.write(data)
                }
                self.activeTransfer?.bytesReceived += Int64(data.count)
            }

            if let error {
                Log.ftp.error("FTP data receive error: \(error.localizedDescription)")
                self.finishTransfer(success: false, error: error.localizedDescription)
                return
            }

            if isComplete {
                self.finishTransfer(success: true, error: nil)
            } else {
                self.receiveFileData(on: conn)
            }
        }
    }

    private func finishTransfer(success: Bool, error: String?) {
        ioQueue.async { [weak self] in
            self?.fileHandle?.closeFile()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.fileHandle = nil

                if success {
                    self.activeTransfer?.isComplete = true
                    if let transfer = self.activeTransfer {
                        let mb = String(format: "%.1f MB", Double(transfer.bytesReceived) / (1024.0 * 1024.0))
                        Log.ftp.info("FTP transfer complete: \(transfer.fileName) (\(mb))")
                        self.onTransferComplete?(transfer)
                    }
                    self.send("226 Transfer complete\r\n")
                } else {
                    self.activeTransfer?.error = error
                    if let transfer = self.activeTransfer {
                        var failed = transfer
                        failed.error = error
                        self.onTransferComplete?(failed)
                    }
                    self.send("426 Transfer aborted\r\n")
                }

                self.activeTransfer = nil
                self.closeDataConnection()
                self.server?.basePathURL?.stopAccessingSecurityScopedResource()
            }
        }
    }

    // MARK: - Data Connection Helpers

    private func closeDataConnection() {
        dataConnection?.cancel()
        dataConnection = nil
        dataListener?.cancel()
        dataListener = nil
    }

    // MARK: - Local IP

    private func localIPAddress() -> String {
        // Try to extract from control connection's local endpoint
        if let localEndpoint = connection.currentPath?.localEndpoint,
           case .hostPort(let host, _) = localEndpoint {
            let hostStr = "\(host)"
            // NWEndpoint.Host wraps IPv4 as-is
            if hostStr.contains(".") && !hostStr.hasPrefix("127.") {
                return hostStr
            }
        }

        // Fallback: enumerate network interfaces
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(sa.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }

        return address
    }
}
