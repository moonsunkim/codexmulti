import Foundation
import Security

public enum Signatures {
    public static let teamIdentifier = "W9AVC25Z2L"
    public static let bundleIdentifier = "dev.codexmulti.app"

    public static func verify(_ url: URL, bundle: Bool = true) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
              let code else { throw UpdateFailure.invalidSignature }
        let requirementText = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
            + (bundle ? " and identifier \"\(bundleIdentifier)\"" : "")
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code,
                SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures),
                requirement) == errSecSuccess else { throw UpdateFailure.invalidSignature }
    }
}
