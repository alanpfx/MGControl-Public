import XCTest
import SwiftUI
@testable import MGDesignWorkbench

final class ThemeTests:XCTestCase {
    func testRoundTripPreservesEveryEditedParameter() throws {
        var t=Theme.initial;t.items["lock"]?.diameter=72;t.items["heat"]?.gap=11;t.cardOrder.reverse();t.accent="AABBCC";t.name="设计师方案一"
        XCTAssertEqual(try Theme.decode(t.data()),t)
    }
    func testRejectsUnsupportedSchemaAndMissingComponents() throws {
        var t=Theme.initial;t.schemaVersion=99;XCTAssertThrowsError(try t.validate())
        t = .initial;t.items.removeValue(forKey:"lock");XCTAssertThrowsError(try t.validate())
    }
    func testRejectsInvalidColorAndUnboundedLayout() throws {
        var t=Theme.initial;t.accent="http://example.com";XCTAssertThrowsError(try t.validate())
        t = .initial;t.padding=10000;XCTAssertThrowsError(try t.validate())
        t = .initial;t.items["lock"]?.iconSize = .infinity;XCTAssertThrowsError(try t.validate())
    }
    func testRejectsDuplicateCardsAndOversizedInput() throws {
        var t=Theme.initial;t.cardOrder=["climate","climate","details","sentinel"];XCTAssertThrowsError(try t.validate())
        XCTAssertThrowsError(try Theme.decode(Data(repeating:32,count:512*1024+1)))
    }
    @MainActor func testNativeRendererForBothPagesAndThemes() throws {
        guard #available(iOS 16.0,*) else {throw XCTSkip("Renderer needs iOS16")}
        for dark in [false,true] {for comfort in [false,true] {
            let view=DesignRenderer(theme:.initial,comfortPage:comfort).frame(width:390,height:844).environment(\.colorScheme,dark ? .dark : .light)
            let renderer=ImageRenderer(content:view);renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage);XCTAssertEqual(image.size.width,390)
            let attachment=XCTAttachment(image:image);attachment.name="design-\(dark)-\(comfort)";attachment.lifetime = .keepAlways;add(attachment)
        }}
    }
}
