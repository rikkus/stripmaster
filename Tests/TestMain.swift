import Foundation

@main
struct TestMain {
    @MainActor
    static func main() async {
        _ = await runAllFunctionalTests()
    }
}
