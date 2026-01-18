#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import WinSDK
#else
import Glibc
#endif
import Foundation

public enum ProviderVersionDetector {
    public static func codexVersion() -> String? {
        guard let path = TTYCommandRunner.which("codex") else { return nil }
        let candidates = [
            ["--version"],
            ["version"],
            ["-v"],
        ]
        for args in candidates {
            if let version = Self.run(path: path, args: args) { return version }
        }
        return nil
    }

    public static func geminiVersion() -> String? {
        let env = ProcessInfo.processInfo.environment
        guard let path = BinaryLocator.resolveGeminiBinary(env: env, loginPATH: nil)
            ?? TTYCommandRunner.which("gemini") else { return nil }
        let candidates = [
            ["--version"],
            ["-v"],
        ]
        for args in candidates {
            if let version = Self.run(path: path, args: args) { return version }
        }
        return nil
    }

    private static func run(path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(2.0)
        while proc.isRunning, Date() < deadline {
            #if os(Windows)
            Thread.sleep(forTimeInterval: 0.05)
            #else
            usleep(50000)
            #endif
        }
        if proc.isRunning {
            proc.terminate()
            let killDeadline = Date().addingTimeInterval(0.5)
            while proc.isRunning, Date() < killDeadline {
                #if os(Windows)
                Thread.sleep(forTimeInterval: 0.02)
                #else
                usleep(20000)
                #endif
            }
            #if !os(Windows)
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
            #endif
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)?
                  .split(whereSeparator: \.isNewline).first
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
