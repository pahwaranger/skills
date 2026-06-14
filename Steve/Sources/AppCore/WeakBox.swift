/// A Sendable weak-reference container, used in `AppModel.init` to break
/// the closure → `self` reference cycle in the `performCheck` wrapper
/// while still allowing the closure to call back onto the main actor.
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init() {}
}
