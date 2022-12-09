//
//  Constructor.swift
//  Yams
//
//  Created by Norio Nomura on 12/21/16.
//  Copyright (c) 2016 Yams. All rights reserved.
//

/// Constructors are used to translate `Node`s to Swift values.
public final class Constructor {
    /// Maps `Tag.Name`s to `Node.Scalar`s.
    public typealias ScalarMap = [Tag.Name: (Node.Scalar) -> Any?]
    /// Maps `Tag.Name`s to `Node.Mapping`s.
    public typealias MappingMap = [Tag.Name: (Node.Mapping) -> Any?]
    /// Maps `Tag.Name`s to `Node.Sequence`s.
    public typealias SequenceMap = [Tag.Name: (Node.Sequence) -> Any?]

    /// Initialize a `Constructor` with the specified maps, falling back to default maps.
    ///
    /// - parameter scalarMap:   Maps `Tag.Name`s to `Node.Scalar`s.
    /// - parameter mappingMap:  Maps `Tag.Name`s to `Node.Mapping`s.
    /// - parameter sequenceMap: Maps `Tag.Name`s to `Node.Sequence`s.
    public init(_ scalarMap: ScalarMap = defaultScalarMap,
                _ mappingMap: MappingMap = defaultMappingMap,
                _ sequenceMap: SequenceMap = defaultSequenceMap) {
        self.scalarMap = scalarMap
        self.mappingMap = mappingMap
        self.sequenceMap = sequenceMap
    }

    /// Constructs Swift values based on the maps this `Constructor` was initialized with.
    ///
    /// - parameter node: `Node` from which to extract an `Any` Swift value, if one was produced by the Node
    ///                   type's relevant mapping on this `Constructor`.
    ///
    /// - returns: An `Any` Swift value, if one was produced by the Node type's relevant mapping on this
    ///            `Constructor`.
    public func any(from node: Node) -> Any {
        switch node {
        case .scalar(let scalar):
            if let method = scalarMap[node.tag.name], let result = method(scalar) {
                return result
            }
            return String.construct(from: scalar)!
        case .mapping(let mapping):
            if let method = mappingMap[node.tag.name], let result = method(mapping) {
                return result
            }
            return [AnyHashable: Any]._construct_mapping(from: mapping)
        case .sequence(let sequence):
            if let method = sequenceMap[node.tag.name], let result = method(sequence) {
                return result
            }
            return [Any].construct_seq(from: sequence)
        }
    }

    private let scalarMap: ScalarMap
    private let mappingMap: MappingMap
    private let sequenceMap: SequenceMap
}

// MARK: - Default Mappings

extension Constructor {
    /// The default `Constructor` to be used with APIs where none is explicitly provided.
    public static let `default` = Constructor()

    /// The default `Tag.Name` to `Node.Scalar` map.
    public static let defaultScalarMap: ScalarMap = [
        // Failsafe Schema
        .str: String.construct,
        // JSON Schema
        .bool: Bool.construct,
        .float: Double.construct,
        .int: MemoryLayout<Int>.size == 8 ? Int.construct : { Int.construct(from: $0) ?? Int64.construct(from: $0) }
    ]

    /// The default `Tag.Name` to `Node.Mapping` map.
    public static let defaultMappingMap: MappingMap = [
        .map: [AnyHashable: Any].construct_mapping,
        // http://yaml.org/type/index.html
        .set: Set<AnyHashable>.construct_set
        // .merge is supported in `[AnyHashable: Any].construct_mapping`.
        // .value is supported in `String.construct` and `[AnyHashable: Any].construct_mapping`.
    ]

    /// The default `Tag.Name` to `Node.Sequence` map.
    public static let defaultSequenceMap: SequenceMap = [
        .seq: [Any].construct_seq,
        // http://yaml.org/type/index.html
        .omap: [Any].construct_omap,
        .pairs: [Any].construct_pairs
    ]
}

// MARK: - ScalarConstructible

/// Types conforming to this protocol can be extracted `Node.Scalar`s.
public protocol ScalarConstructible {
    /// Construct an instance of `Self`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `Self`, if possible.
    ///
    /// - returns: An instance of `Self`, if one was successfully extracted from the scalar.
    ///
    /// - note: We use static constructors to avoid overloading `init?(_ scalar: Node.Scalar)` which would
    ///         cause callsite ambiguities when using `init` as closure.
    static func construct(from scalar: Node.Scalar) -> Self?
}

// MARK: - ScalarConstructible Bool Conformance

extension Bool: ScalarConstructible {
    /// Construct an instance of `Bool`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `Bool`, if possible.
    ///
    /// - returns: An instance of `Bool`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> Bool? {
        switch scalar.string.lowercased() {
        case "true", "yes", "on":
            return true
        case "false", "no", "off":
            return false
        default:
            return nil
        }
    }
}

// MARK: - ScalarConstructible Double Conformance
extension Double: ScalarConstructible {}
// MARK: - ScalarConstructible Float Conformance
extension Float: ScalarConstructible {}

// MARK: - ScalarConstructible FloatingPoint Conformance
extension ScalarConstructible where Self: FloatingPoint & SexagesimalConvertible {
    /// Construct an instance of `FloatingPoint & SexagesimalConvertible`, if possible, from the specified
    /// scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type
    ///                     `FloatingPoint & SexagesimalConvertible`, if possible.
    ///
    /// - returns: An instance of `FloatingPoint & SexagesimalConvertible`, if one was successfully extracted
    ///            from the scalar.
    public static func construct(from scalar: Node.Scalar) -> Self? {
        guard scalar.style == .any || scalar.style == .plain else {
            return nil
        }

        switch scalar.string {
        case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF":
            return .infinity
        case "-.inf", "-.Inf", "-.INF":
            return -.infinity
        case ".nan", ".NaN", ".NAN":
            return .nan
        default:
            let string = scalar.string.replacing("_", with: "")
            if string.contains(":") {
                return Self(sexagesimal: string)
            }
            return .create(from: string)
        }
    }
}

private extension FixedWidthInteger where Self: SexagesimalConvertible {
    static func _construct(from scalar: Node.Scalar) -> Self? {
        guard scalar.style == .any || scalar.style == .plain else {
            return nil
        }

        let scalarWithSign = scalar.string.replacing("_", with: "")

        if scalarWithSign == "0" {
            return 0
        }

        let negative = scalarWithSign.hasPrefix("-")

        guard isSigned || !negative else { return nil }

        let signPrefix = negative ? "-" : ""
        let hasSign = negative || scalarWithSign.hasPrefix("+")

        let prefixToRadix: [(String, Int)] = [
            ("0x", 16),
            ("0b", 2),
            ("0o", 8),
            ("0", 8)
        ]

        let scalar = scalarWithSign.dropFirst(hasSign ? 1 : 0)
        for (prefix, radix) in prefixToRadix where scalar.hasPrefix(prefix) {
            return Self(signPrefix + scalar.dropFirst(prefix.count), radix: radix)
        }
        if scalar.contains(":") {
            return Self(sexagesimal: scalarWithSign)
        }
        return Self(scalarWithSign)
    }
}

// MARK: - ScalarConstructible Int Conformance

extension Int: ScalarConstructible {
    /// Construct an instance of `Int`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `Int`, if possible.
    ///
    /// - returns: An instance of `Int`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> Int? {
        return _construct(from: scalar)
    }
}

// MARK: - ScalarConstructible UInt Conformance

extension UInt: ScalarConstructible {
    /// Construct an instance of `UInt`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `UInt`, if possible.
    ///
    /// - returns: An instance of `UInt`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> UInt? {
        return _construct(from: scalar)
    }
}

// MARK: - ScalarConstructible Int64 Conformance

extension Int64: ScalarConstructible {
    /// Construct an instance of `Int64`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `Int64`, if possible.
    ///
    /// - returns: An instance of `Int64`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> Int64? {
        return _construct(from: scalar)
    }
}

// MARK: - ScalarConstructible UInt64 Conformance

extension UInt64: ScalarConstructible {
    /// Construct an instance of `UInt64`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `UInt64`, if possible.
    ///
    /// - returns: An instance of `UInt64`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> UInt64? {
        return _construct(from: scalar)
    }
}

// MARK: - ScalarConstructible String Conformance

extension String: ScalarConstructible {
    /// Construct an instance of `String`, if possible, from the specified scalar.
    ///
    /// - parameter scalar: The `Node.Scalar` from which to extract a value of type `String`, if possible.
    ///
    /// - returns: An instance of `String`, if one was successfully extracted from the scalar.
    public static func construct(from scalar: Node.Scalar) -> String? {
        return scalar.string
    }

    /// Construct an instance of `String`, if possible, from the specified `Node`.
    ///
    /// - parameter node: The `Node` from which to extract a value of type `String`, if possible.
    ///
    /// - returns: An instance of `String`, if one was successfully extracted from the node.
    public static func construct(from node: Node) -> String? {
        // This will happen while `Dictionary.flatten_mapping()` if `node.tag.name` was `.value`
        if case let .mapping(mapping) = node {
            for (key, value) in mapping where key.tag.name == .value {
                return construct(from: value)
            }
        }

        return node.scalar?.string
    }
}

// MARK: Mapping

extension Dictionary {
    /// Construct a `Dictionary`, if possible, from the specified mapping.
    ///
    /// - parameter mapping: The `Node.Mapping` from which to extract a `Dictionary`, if possible.
    ///
    /// - returns: An instance of `[AnyHashable: Any]`, if one was successfully extracted from the mapping.
    public static func construct_mapping(from mapping: Node.Mapping) -> [AnyHashable: Any]? {
        return _construct_mapping(from: mapping)
    }
}

private extension Dictionary {
    static func _construct_mapping(from mapping: Node.Mapping) -> [AnyHashable: Any] {
        let mapping = mapping.flatten()
        // TODO: YAML supports keys other than str.
        return [AnyHashable: Any](
            mapping.map { (String.construct(from: $0.key)!, mapping.tag.constructor.any(from: $0.value)) },
            uniquingKeysWith: { _, second in second }
        )
    }
}

extension Set {
    /// Construct a `Set`, if possible, from the specified mapping.
    ///
    /// - parameter mapping: The `Node.Mapping` from which to extract a `Set`, if possible.
    ///
    /// - returns: An instance of `Set<AnyHashable>`, if one was successfully extracted from the mapping.
    public static func construct_set(from mapping: Node.Mapping) -> Set<AnyHashable>? {
        // TODO: YAML supports Hashable elements other than str.
        return Set<AnyHashable>(mapping.map({ String.construct(from: $0.key)! as AnyHashable }))
        // Explicitly declaring the generic parameter as `<AnyHashable>` above is required,
        // because this is inside extension of `Set` and Swift can't infer the type without that.
    }
}

// MARK: Sequence

extension Array {
    /// Construct an Array of `Any` from the specified `sequence`.
    ///
    /// - parameter sequence: Sequence to convert to `Array<Any>`.
    ///
    /// - returns: Array of `Any`.
    public static func construct_seq(from sequence: Node.Sequence) -> [Any] {
        return sequence.map(sequence.tag.constructor.any)
    }

    /// Construct an "O-map" (array of `(Any, Any)` tuples) from the specified `sequence`.
    ///
    /// - parameter sequence: Sequence to convert to `Array<(Any, Any)>`.
    ///
    /// - returns: Array of `(Any, Any)` tuples.
    public static func construct_omap(from sequence: Node.Sequence) -> [(Any, Any)] {
        // Note: we do not check for duplicate keys.
        return sequence.compactMap { subnode -> (Any, Any)? in
            // TODO: Should raise error if subnode is not mapping or mapping.count != 1
            guard let (key, value) = subnode.mapping?.first else { return nil }
            return (sequence.tag.constructor.any(from: key), sequence.tag.constructor.any(from: value))
        }
    }

    /// Construct an array of `(Any, Any)` tuples from the specified `sequence`.
    ///
    /// - parameter sequence: Sequence to convert to `Array<(Any, Any)>`.
    ///
    /// - returns: Array of `(Any, Any)` tuples.
    public static func construct_pairs(from sequence: Node.Sequence) -> [(Any, Any)] {
        // Note: we do not check for duplicate keys.
        return sequence.compactMap { subnode -> (Any, Any)? in
            // TODO: Should raise error if subnode is not mapping or mapping.count != 1
            guard let (key, value) = subnode.mapping?.first else { return nil }
            return (sequence.tag.constructor.any(from: key), sequence.tag.constructor.any(from: value))
        }
    }
}

// MARK: - SexagesimalConvertible

/// Confirming types are convertible to base 60 numeric values.
public protocol SexagesimalConvertible: ExpressibleByIntegerLiteral {
    /// Creates a sexagesimal numeric value from the given string.
    ///
    /// - parameter string: The string from which to parse a sexagesimal value.
    ///
    /// - returns: A sexagesimal numeric value, if one was successfully parsed.
    static func create(from string: String) -> Self?

    /// Multiplies two sexagesimal numeric values.
    ///
    /// - parameter lhs: Left hand side multiplier.
    /// - parameter rhs: Right hand side multiplier.
    ///
    /// - returns: The result of the multiplication.
    static func * (lhs: Self, rhs: Self) -> Self

    /// Adds two sexagesimal numeric values.
    ///
    /// - parameter lhs: Left hand side adder.
    /// - parameter rhs: Right hand side adder.
    ///
    /// - returns: The result of the addition.
    static func + (lhs: Self, rhs: Self) -> Self
}

private extension SexagesimalConvertible {
    init(sexagesimal value: String) {
        self = value.sexagesimal()
    }
}

// MARK: Default String to `LosslessStringConvertible` conversion.

extension SexagesimalConvertible where Self: LosslessStringConvertible {
    /// Creates a sexagesimal numeric value from the given string.
    ///
    /// - parameter string: The string from which to parse a sexagesimal value.
    ///
    /// - returns: A sexagesimal numeric value, if one was successfully parsed.
    public static func create(from string: String) -> Self? {
        return Self(string)
    }
}

// MARK: Default String to `FixedWidthInteger` conversion.

extension SexagesimalConvertible where Self: FixedWidthInteger {
    /// Creates a sexagesimal numeric value from the given string.
    ///
    /// - parameter string: The string from which to parse a sexagesimal value.
    ///
    /// - returns: A sexagesimal numeric value, if one was successfully parsed.
    public static func create(from string: String) -> Self? {
        return Self(string, radix: 10)
    }
}

// MARK: - SexagesimalConvertible Double Conformance
extension Double: SexagesimalConvertible {}
// MARK: - SexagesimalConvertible Float Conformance
extension Float: SexagesimalConvertible {}
// MARK: - SexagesimalConvertible Int Conformance
extension Int: SexagesimalConvertible {}
// MARK: - SexagesimalConvertible UInt Conformance
extension UInt: SexagesimalConvertible {}
// MARK: - SexagesimalConvertible Int64 Conformance
extension Int64: SexagesimalConvertible {}
// MARK: - SexagesimalConvertible UInt64 Conformance
extension UInt64: SexagesimalConvertible {}

private extension String {
    func sexagesimal<T>() -> T where T: SexagesimalConvertible {
        assert(contains(":"))
        var scalar = self

        let sign: T
        if scalar.hasPrefix("-") {
            sign = -1
            scalar = String(scalar.dropFirst())
        } else if scalar.hasPrefix("+") {
            scalar = String(scalar.dropFirst())
            sign = 1
        } else {
            sign = 1
        }
        let digits = scalar.split(separator: ":").map(String.init).compactMap(T.create).reversed()
        let (_, value) = digits.reduce((1, 0) as (T, T)) { baseAndValue, digit in
            let value = baseAndValue.1 + (digit * baseAndValue.0)
            let base = baseAndValue.0 * 60
            return (base, value)
        }
        return sign * value
    }
}

// swiftlint:disable:this file_length
