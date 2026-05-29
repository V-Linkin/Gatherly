import XCTest
@testable import Archiver

final class BrowserDetectorTests: XCTestCase {
    var browserDetector: BrowserDetector!
    
    override func setUp() {
        super.setUp()
        browserDetector = BrowserDetector.shared
    }
    
    override func tearDown() {
        // 清理测试数据
        UserDefaults.standard.removeObject(forKey: "selectedBrowserBundleIdentifier")
        super.tearDown()
    }
    
    func testGetAvailableBrowsers() {
        // Given
        // When
        let browsers = browserDetector.getAvailableBrowsers()
        
        // Then
        XCTAssertFalse(browsers.isEmpty, "应该检测到至少一个浏览器")
        
        // 验证每个浏览器都有有效的信息
        for browser in browsers {
            XCTAssertFalse(browser.bundleIdentifier.isEmpty)
            XCTAssertFalse(browser.name.isEmpty)
            XCTAssertFalse(browser.version.isEmpty)
        }
    }
    
    func testGetSelectedBrowserBundleIdentifier() {
        // Given
        let testBundleId = "com.apple.Safari"
        
        // When
        browserDetector.setSelectedBrowser(testBundleId)
        let retrievedBundleId = browserDetector.getSelectedBrowserBundleIdentifier()
        
        // Then
        XCTAssertEqual(retrievedBundleId, testBundleId)
    }
    
    func testSetSelectedBrowserWithEmptyString() {
        // Given
        let emptyBundleId = ""
        
        // When
        browserDetector.setSelectedBrowser(emptyBundleId)
        let retrievedBundleId = browserDetector.getSelectedBrowserBundleIdentifier()
        
        // Then
        XCTAssertEqual(retrievedBundleId, emptyBundleId)
    }
    
    func testGetSelectedBrowserName() {
        // Given
        // 测试默认情况
        browserDetector.setSelectedBrowser("")
        
        // When
        let name = browserDetector.getSelectedBrowserName()
        
        // Then
        XCTAssertEqual(name, "系统默认")
    }
    
    func testIsBrowserAvailable() {
        // Given
        let safariBundleId = "com.apple.Safari"
        let invalidBundleId = "com.nonexistent.browser"
        
        // When
        let safariAvailable = browserDetector.isBrowserAvailable(safariBundleId)
        let invalidAvailable = browserDetector.isBrowserAvailable(invalidBundleId)
        
        // Then
        XCTAssertTrue(safariAvailable, "Safari应该可用")
        XCTAssertFalse(invalidAvailable, "不存在的浏览器应该不可用")
    }
}
