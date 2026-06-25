import XCTest
@testable import AIDashCore

final class URLPolicyTests: XCTestCase {

    func test_validate_acceptsHttps() {
        XCTAssertEqual(
            URLPolicy.validate("https://example.com/pr/4521")?.absoluteString,
            "https://example.com/pr/4521"
        )
    }

    func test_validate_rejectsHttp() {
        XCTAssertNil(URLPolicy.validate("http://example.com"))
    }

    func test_validate_rejectsJavascript() {
        XCTAssertNil(URLPolicy.validate("javascript:alert(1)"))
    }

    func test_validate_rejectsAbout() {
        XCTAssertNil(URLPolicy.validate("about:blank"))
    }

    func test_validate_rejectsFile() {
        XCTAssertNil(URLPolicy.validate("file:///etc/passwd"))
    }

    func test_validate_rejectsCustomScheme() {
        XCTAssertNil(URLPolicy.validate("foo://bar"))
    }

    func test_validate_rejectsMissingHost() {
        XCTAssertNil(URLPolicy.validate("https:///foo"))
    }

    func test_validate_rejectsEmptyAndNil() {
        XCTAssertNil(URLPolicy.validate(nil))
        XCTAssertNil(URLPolicy.validate(""))
    }

    func test_validate_rejectsGarbage() {
        XCTAssertNil(URLPolicy.validate("not a url at all"))
    }
}
