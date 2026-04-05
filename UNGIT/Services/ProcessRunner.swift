import Foundation

struct CommandResult {
    let exitCode: Int32
    let output: String
}

struct ProcessRunner {
    func run(_ launchPath: String, _ arguments: [String], currentDirectoryURL: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            let details = [output.trimmed, error.trimmed].filter { !$0.isEmpty }.joined(separator: " | ")
            throw AppError.commandFailed(details.isEmpty ? "exit code \(process.terminationStatus)" : details)
        }
    }

    func runCapturing(_ launchPath: String, _ arguments: [String], currentDirectoryURL: URL? = nil) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        let details = [output.trimmed, error.trimmed].filter { !$0.isEmpty }.joined(separator: "\n")
        return CommandResult(exitCode: process.terminationStatus, output: details)
    }
}
