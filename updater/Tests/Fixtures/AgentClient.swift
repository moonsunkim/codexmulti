import Foundation
import UpdaterKit

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else { throw UpdateFailure.invalidCommand }
    let store = try RuntimeStore(root: URL(fileURLWithPath: arguments[1]))
    let state = try AgentConnection.send(AgentRequest(arguments[3], transactionID: arguments[2]), store: store)
    print(state.phase.rawValue)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
