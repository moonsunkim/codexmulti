import Foundation



enum KeychainProbeLaunch {
    static let bufferCapacity = 64 * 1024

    @discardableResult
    static func run(
        abi: CoreABI = .live,
        writeStandardOutput: (Data) -> Void = { FileHandle.standardOutput.write($0) },
        writeStandardError: (Data) -> Void = { FileHandle.standardError.write($0) }
    ) -> Int32 {
        guard let handle = abi.create() else {
            writeStandardError(Data("CodexMulti: keychain probe could not create core\n".utf8))
            return 1
        }
        defer { abi.destroy(handle) }

        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferCapacity)
        defer { buffer.deallocate() }
        let result = abi.keychainProbe(handle, buffer, bufferCapacity)
        guard result >= 0 else {
            writeStandardError(Data("CodexMulti: keychain probe failed (\(result))\n".utf8))
            return 1
        }
        guard result <= bufferCapacity else {
            writeStandardError(Data("CodexMulti: keychain probe returned an invalid byte count\n".utf8))
            return 1
        }

        writeStandardOutput(Data(bytes: buffer, count: Int(result)))
        return 0
    }
}
