import Cocoa
import FlutterMacOS
import XCTest

@testable import Penchant

class RunnerTests: XCTestCase {

  func testOpensAtTheDefaultSizeWhereItFits() {
    XCTAssertEqual(
      MainFlutterWindow.initialContentSize(fitting: NSSize(width: 2560, height: 1400)),
      NSSize(width: 1200, height: 780))
  }

  func testShrinksToASmallerScreen() {
    XCTAssertEqual(
      MainFlutterWindow.initialContentSize(fitting: NSSize(width: 1024, height: 700)),
      NSSize(width: 1024, height: 700))
  }

  func testNeverOpensBelowTheMinimum() {
    XCTAssertEqual(
      MainFlutterWindow.initialContentSize(fitting: NSSize(width: 300, height: 400)),
      NSSize(width: 390, height: 600))
  }

  func testTheDefaultIsWideEnoughForTheSplitView() {
    XCTAssertGreaterThanOrEqual(MainFlutterWindow.defaultContentSize.width, 900)
    XCTAssertLessThan(MainFlutterWindow.minimumContentSize.width, 900)
  }

}
