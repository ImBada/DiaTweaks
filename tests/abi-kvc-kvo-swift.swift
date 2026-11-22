import Foundation

private final class DPPureSwiftSelection {
    let allSelectedTabIDs: [String]
    let primarySelectedTabID: String?

    init(primary: String?, all: [String]) {
        self.primarySelectedTabID = primary
        self.allSelectedTabIDs = all
    }
}

private final class DPPureSwiftIDBox {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

@_cdecl("DPMakePureSwiftSelection")
public func DPMakePureSwiftSelection(_ primary: NSString?, _ all: NSArray) -> AnyObject {
    let list = all.compactMap { $0 as? String }
    return DPPureSwiftSelection(primary: primary as String?, all: list)
}

@_cdecl("DPMakePureSwiftIDBox")
public func DPMakePureSwiftIDBox(_ raw: NSString) -> AnyObject {
    DPPureSwiftIDBox(raw as String)
}
