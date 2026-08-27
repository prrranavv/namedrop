import Foundation

@main
struct NameDropHost {
    static func main() {
        guard let resources = Bundle.main.resourceURL else {
            Foundation.exit(2)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let logs = home.appendingPathComponent("Library/Logs/NameDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let outputURL = logs.appendingPathComponent("helper.log")
        let errorURL = logs.appendingPathComponent("helper-error.log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)

        guard let output = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            Foundation.exit(2)
        }
        _ = try? output.seekToEnd()
        _ = try? errorHandle.seekToEnd()

        let worker = Process()
        worker.executableURL = home.appendingPathComponent("Library/Application Support/NameDrop/venv/bin/python3")
        worker.arguments = [resources.appendingPathComponent("renamer.py").path, "watch"]
        var environment = ProcessInfo.processInfo.environment
        environment["NAMEDROP_BINARY"] = resources.appendingPathComponent("bin/namedrop-namer").path
        worker.environment = environment
        worker.standardOutput = output
        worker.standardError = errorHandle

        do {
            try worker.run()
            worker.waitUntilExit()
            Foundation.exit(worker.terminationStatus)
        } catch {
            errorHandle.write(Data("Failed to launch worker: \(error)\n".utf8))
            Foundation.exit(2)
        }
    }
}
