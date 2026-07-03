import BinaryParsing

// `Endianness` is a plain `Bool` wrapper with value semantics; swift-binary-parsing
// just hasn't marked it `Sendable` yet.
extension Endianness: @retroactive @unchecked Sendable {}
