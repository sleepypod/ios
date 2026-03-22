import XCTest
@testable import Sleepypod

final class SanitizeIPTests: XCTestCase {

    // MARK: - Clean IPs pass through unchanged

    func testCleanIPv4Unchanged() {
        XCTAssertEqual(sanitizeIP("192.168.1.88"), "192.168.1.88")
    }

    func testLocalhostUnchanged() {
        XCTAssertEqual(sanitizeIP("127.0.0.1"), "127.0.0.1")
    }

    // MARK: - Zone ID stripping

    func testStripsPercentEn0() {
        XCTAssertEqual(sanitizeIP("192.168.1.88%en0"), "192.168.1.88")
    }

    func testStripsDoublePercentEn0() {
        XCTAssertEqual(sanitizeIP("192.168.1.88%%en0"), "192.168.1.88")
    }

    func testStripsPercentEn1() {
        XCTAssertEqual(sanitizeIP("10.0.0.5%en1"), "10.0.0.5")
    }

    func testStripsPercentFromIPv6() {
        XCTAssertEqual(sanitizeIP("fe80::1%en0"), "fe80::1")
    }

    // MARK: - IPv4-mapped IPv6 prefix

    func testStripsFFFFPrefix() {
        XCTAssertEqual(sanitizeIP("::ffff:192.168.1.88"), "192.168.1.88")
    }

    func testStripsFFFFPrefixWithZoneID() {
        XCTAssertEqual(sanitizeIP("::ffff:192.168.1.88%en0"), "192.168.1.88")
    }

    // MARK: - Whitespace

    func testTrimsWhitespace() {
        XCTAssertEqual(sanitizeIP("  192.168.1.88  "), "192.168.1.88")
    }

    func testTrimsNewline() {
        XCTAssertEqual(sanitizeIP("192.168.1.88\n"), "192.168.1.88")
    }

    // MARK: - Edge cases

    func testEmptyString() {
        XCTAssertEqual(sanitizeIP(""), "")
    }

    func testJustPercent() {
        XCTAssertEqual(sanitizeIP("%en0"), "")
    }

    func testIPv6WithoutZone() {
        XCTAssertEqual(sanitizeIP("fe80::1"), "fe80::1")
    }
}
