// One-time setup: creates the Ed25519 key pair used to sign releases.
// The private key is stored in your login Keychain; the public key is printed for Info.plist.
// Usage: swift scripts/keygen.swift
import CryptoKit
import Foundation

let service = "StatMenu update signing key"
let account = "StatMenu"

let existing = Process()
existing.executableURL = URL(fileURLWithPath: "/usr/bin/security")
existing.arguments = ["find-generic-password", "-a", account, "-s", service]
existing.standardOutput = FileHandle.nullDevice
existing.standardError = FileHandle.nullDevice
try existing.run()
existing.waitUntilExit()
if existing.terminationStatus == 0 {
    print("A signing key already exists in your Keychain (\(service)). Refusing to overwrite it.")
    exit(1)
}

let key = Curve25519.Signing.PrivateKey()
let add = Process()
add.executableURL = URL(fileURLWithPath: "/usr/bin/security")
add.arguments = ["add-generic-password", "-a", account, "-s", service, "-w", key.rawRepresentation.base64EncodedString()]
try add.run()
add.waitUntilExit()
guard add.terminationStatus == 0 else { print("Could not save the key to the Keychain."); exit(1) }

print("Saved the private key to your Keychain as \"\(service)\". Back it up somewhere safe.")
print("Public key (put this in Resources/Info.plist → StatMenuUpdatePublicKey):")
print(key.publicKey.rawRepresentation.base64EncodedString())
