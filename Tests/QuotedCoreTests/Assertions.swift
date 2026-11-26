import Testing

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a == b, Comment(rawValue: note), sourceLocation: sourceLocation)
}
func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a != b, Comment(rawValue: note), sourceLocation: sourceLocation)
}
func expectNil<T>(_ value: T?, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, Comment(rawValue: note), sourceLocation: sourceLocation)
}
func expectNotNil<T>(_ value: T?, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value != nil, Comment(rawValue: note), sourceLocation: sourceLocation)
}
func expectTrue(_ value: Bool, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value, Comment(rawValue: note), sourceLocation: sourceLocation)
}
func expectFalse(_ value: Bool, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!value, Comment(rawValue: note), sourceLocation: sourceLocation)
}
func expectGreaterThan<T: Comparable>(_ a: T, _ b: T, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a > b, Comment(rawValue: note), sourceLocation: sourceLocation)
}
