/// What a store knows about a value it loads: still fetching, fetched, or failed.
///
/// The three states are deliberately distinct so no view ever infers one from
/// another - an empty list is `.loaded([])`, never a stand-in for loading, and a
/// repository error is `.failed`, never an empty list (Wave 3 constraint).
public enum LoadState<Value: Sendable>: Sendable {
    case loading
    case loaded(Value)
    case failed(any Error)

    /// The loaded value, when there is one.
    public var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    public var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    /// The failure, when the load failed.
    public var error: (any Error)? {
        if case .failed(let error) = self { error } else { nil }
    }
}
