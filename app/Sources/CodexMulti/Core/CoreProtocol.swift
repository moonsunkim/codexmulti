import Foundation





protocol CoreProtocol: Sendable {




    func start() async throws

    func submit(_ intent: Intent) async

    func pumpNow() async

    func shutdown() async
}
