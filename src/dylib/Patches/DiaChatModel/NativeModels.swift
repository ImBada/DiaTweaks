import Foundation

@objc(DPNativeChatModelCatalog) final class NativeChatModelCatalog: NSObject {
    @objc static func modelsInType(_ metadata: UInt) -> [String] {
        guard metadata != 0 else { return [] }
        let type = unsafeBitCast(metadata, to: Any.Type.self)
        guard String(reflecting: type) == "BoostFeatureFlags.ChatResponseModel",
              let catalog = type as? any CaseIterable.Type else { return [] }
        return identifiers(in: catalog.allCases)
    }

    private static func identifiers<C: Collection>(in cases: C) -> [String] {
        var seen = Set<String>()
        return cases.compactMap { item in
            guard let entry = item as? any RawRepresentable,
                  let model = entry.rawValue as? String,
                  !model.isEmpty, model.utf8.count <= 256,
                  model.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                  model.rangeOfCharacter(from: .controlCharacters) == nil,
                  seen.insert(model).inserted else { return nil }
            return model
        }
    }
}
