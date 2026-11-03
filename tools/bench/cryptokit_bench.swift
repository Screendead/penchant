// Times CryptoKit AES-256-GCM, the primitive cryptography_flutter calls on
// iOS and macOS, at the app's blob sizes, without the platform channel.
// Also PBKDF2 for scale, though option O1 uses no KDF.
// swift tools/bench/cryptokit_bench.swift
import CommonCrypto
import CryptoKit
import Foundation

func time(_ label: String, _ n: Int, _ body: () throws -> Void) rethrows {
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<n { try body() }
    let ns = Double(DispatchTime.now().uptimeNanoseconds - start)
    print(String(format: "%@: %.1f ms for %d, %.2f us each", label, ns / 1e6, n, ns / 1e3 / Double(n)))
}

let key = SymmetricKey(size: .bits256)
let aad = Data("tracker:v1:activities:a1:alice:v1".utf8)
for size in [64, 256] {
    let plain = Data(count: size)
    var boxes: [AES.GCM.SealedBox] = []
    try time("seal \(size) B", 2000) { boxes.append(try AES.GCM.seal(plain, using: key, authenticating: aad)) }
    var i = 0
    try time("open \(size) B", 2000) { _ = try AES.GCM.open(boxes[i], using: key, authenticating: aad); i += 1 }
}

for rounds in [UInt32(210_000), UInt32(600_000)] {
    var derived = [UInt8](repeating: 0, count: 32)
    let salt = [UInt8](repeating: 1, count: 16)
    time("PBKDF2-HMAC-SHA256 \(rounds) rounds", 1) {
        _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), "correct horse", 13, salt, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &derived, 32)
    }
}
