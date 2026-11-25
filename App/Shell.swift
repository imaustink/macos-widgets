import Foundation

// Running CLI tools (kubectl, aws, ssh) from a GUI app.

/// Apps launched from Finder/login don't inherit the shell's environment, so tools installed via
/// Homebrew, asdf, Nix, etc. wouldn't be found and a custom KUBECONFIG would be ignored. We ask the
/// user's login shell once at startup and use its PATH and KUBECONFIG for every command.
private let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
nonisolated(unsafe) private var loginEnv: [String: String] = [:]

func loadLoginShellEnvironment() async {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let marker = "__KUBEWIDGET_ENV__"
    // -i so rc files that set PATH (e.g. ~/.zshrc) are read too; markers fence off any banner output.
    let script = "printf '\\n\(marker)\\n%s\\n%s\\n\(marker)\\n' \"$PATH\" \"$KUBECONFIG\""
    let r = await run(shell, ["-lic", script], env: ProcessInfo.processInfo.environment, timeout: 10)
    let parts = r.out.components(separatedBy: marker)
    guard parts.count >= 3 else { return }
    let lines = parts[1].split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count >= 3 else { return }
    if !lines[1].isEmpty { loginEnv["PATH"] = lines[1] }
    if !lines[2].isEmpty { loginEnv["KUBECONFIG"] = lines[2] }
}

struct ShellResult { let code: Int32; let out: String; let err: String }

/// Runs `exe args…` (looked up on PATH) and returns its output. Killed after `timeout` seconds.
func sh(_ exe: String, _ args: [String], timeout: TimeInterval = 12) async -> ShellResult {
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = [loginEnv["PATH"], fallbackPath, env["PATH"]].compactMap { $0 }.joined(separator: ":")
    if let kc = loginEnv["KUBECONFIG"] { env["KUBECONFIG"] = kc }
    return await run("/usr/bin/env", [exe] + args, env: env, timeout: timeout)
}

private func run(_ path: String, _ args: [String], env: [String: String], timeout: TimeInterval) async -> ShellResult {
    await withCheckedContinuation { cont in
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.environment = env
            p.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do { try p.run() } catch {
                cont.resume(returning: ShellResult(code: -1, out: "", err: "\(error)"))
                return
            }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            var errData = Data()
            let errReader = DispatchWorkItem { errData = err.fileHandleForReading.readDataToEndOfFile() }
            DispatchQueue.global().async(execute: errReader)
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            errReader.wait()
            killer.cancel()
            cont.resume(returning: ShellResult(
                code: p.terminationStatus,
                out: String(decoding: outData, as: UTF8.self),
                err: String(decoding: errData, as: UTF8.self)))
        }
    }
}
