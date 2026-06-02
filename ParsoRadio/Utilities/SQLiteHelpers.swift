import SQLite

/// Helper for creating column expressions that works around
/// Swift 6 / Xcode 16 incompatible overload resolution with
/// SQLite.swift's `Expression` initializers.
/// Usage: `private let colId = Column<String>("id").expr`
struct Column<T> {
    let expr: Expression<T>
    init(_ name: String) {
        self.expr = Expression<T>("\"\(name)\"", [Binding?]())
    }
}
