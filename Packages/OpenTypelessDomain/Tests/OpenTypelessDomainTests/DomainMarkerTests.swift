import XCTest

@testable import OpenTypelessDomain

final class DomainMarkerTests: XCTestCase {
    func testDomainPackageLoads() {
        _ = OpenTypelessDomain.self
    }
}
