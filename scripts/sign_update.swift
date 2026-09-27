// Signs a release file with the private key from your Keychain and prints the base64 signature.
// Usage: swift scripts/sign_update.swift path/to/StatMenu.zip
import CryptoKit
import Foundation

let service = "StatMenu update signing key"
let account = "StatMenu"
guard CommandLine.arguments.count == 2 else { print("Usage: sign_update.swift <file>"); exit(1) }

let find = Process()
let pipe = Pipe()
find.executableURL = URL(fileURLWithPath: "/usr/bin/security")
find.arguments = ["find-generic-password", "-a", account, "-s", service, "-w"]
find.standardOutput = pipe
try find.run()
find.waitUntilExit()
let secret = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
guard find.terminationStatus == 0, let raw = Data(base64Encoded: secret),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    print("No signing key found in the Keychain. Run scripts/keygen.swift first."); exit(1)
}
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
print(try key.signature(for: data).base64EncodedString())
