import XCTest
import SwiftUI
import UIKit
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
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first)
        var screenshots=Set<Data>()
        for dark in [false,true] {for comfort in [false,true] {
            let view=DesignRenderer(theme:.initial,comfortPage:comfort).frame(width:390,height:844).environment(\.colorScheme,dark ? .dark : .light)
            let host=UIHostingController(rootView:view)
            let window=UIWindow(windowScene:scene);window.frame=CGRect(x:0,y:0,width:390,height:844)
            window.rootViewController=host;window.makeKeyAndVisible()
            host.view.frame=window.bounds;host.view.setNeedsLayout();host.view.layoutIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.4))
            let image=UIGraphicsImageRenderer(size:window.bounds.size).image {_ in host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true)}
            XCTAssertEqual(image.size.width,390)
            screenshots.insert(try XCTUnwrap(image.pngData()))
            let attachment=XCTAttachment(image:image);attachment.name="design-\(dark)-\(comfort)";attachment.lifetime = .keepAlways;add(attachment)
            window.isHidden=true
        }}
        XCTAssertEqual(screenshots.count,4,"Pages and themes must produce distinct nonblank captures")
    }
}
