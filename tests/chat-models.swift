import Foundation

#if MISSING_CATALOG
enum OtherResponseModel: String, CaseIterable {
    case future = "future-provider-model"
}
@_cdecl("DPKeepFixtureMetadata") func keepFixtureMetadata() -> UInt {
    unsafeBitCast(OtherResponseModel.self as Any.Type, to: UInt.self)
}
#elseif GENERIC_CATALOG
enum ChatResponseModel<Value>: String, CaseIterable {
    case future = "future-provider-model"
}
@_cdecl("DPKeepFixtureMetadata") func keepFixtureMetadata() -> UInt {
    unsafeBitCast(ChatResponseModel<Int>.self as Any.Type, to: UInt.self)
}
#elseif NO_CASES
enum ChatResponseModel: String {
    case future = "future-provider-model"
}
@_cdecl("DPKeepFixtureMetadata") func keepFixtureMetadata() -> UInt {
    unsafeBitCast(ChatResponseModel.self as Any.Type, to: UInt.self)
}
#else
enum ChatResponseModel: String, CaseIterable {
    case first = "future-provider-model"
    case second = "another-model-v99"
    case third = "another-model-v99[huge]"
    case invalid = "not a model identifier"
}
@_cdecl("DPKeepFixtureMetadata") func keepFixtureMetadata() -> UInt {
    unsafeBitCast(ChatResponseModel.self as Any.Type, to: UInt.self)
}
#endif
