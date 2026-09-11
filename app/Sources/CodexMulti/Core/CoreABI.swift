import Foundation
import CMCore





typealias CoreHandle = OpaquePointer




struct CoreABI: Sendable {
    var version: @Sendable () -> UInt32

    var provenance: @Sendable () -> String
    var create: @Sendable () -> CoreHandle?
    var destroy: @Sendable (CoreHandle) -> Void

    var submit: @Sendable (CoreHandle, Data) -> Int32
    var pump: @Sendable (CoreHandle, Int64) -> Void

    var project: @Sendable (CoreHandle) -> Data?

    var keychainProbe: @Sendable (CoreHandle, UnsafeMutablePointer<CChar>, Int) -> Int32

    static let live = CoreABI(
        version: { cm_service_version() },
        provenance: { String(cString: cm_service_provenance()) },
        create: { cm_service_create() },
        destroy: { cm_service_destroy($0) },
        submit: { handle, json in
            String(decoding: json, as: UTF8.self).withCString { cm_service_submit(handle, $0) }
        },
        pump: { cm_service_pump($0, $1) },
        project: { handle in
            guard let buffer = cm_service_project(handle) else { return nil }
            return Data(bytes: buffer, count: strlen(buffer))
        },
        keychainProbe: { handle, out, capacity in
            cm_service_keychain_probe(handle, out, capacity)
        }
    )
}
