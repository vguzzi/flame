import 'package:ordered_set/comparing.dart';
import 'package:ordered_set/queryable_ordered_set.dart';

import '../../components.dart';
import '../game/base_game.dart';

/// This is a simple wrapper over [QueryableOrderedSet] to be used by
/// [BaseGame] and [BaseComponent].
///
/// Instead of immediately modifying the component list, all insertion
/// and removal operations are queued to be performed on the next tick.
///
/// This will avoid any concurrent modification exceptions while the game
/// iterates through the component list.
///
/// This wrapper also guaranteed that prepare, onLoad, onMount and all the
/// lifecycle methods are called properly.
class ComponentSet extends QueryableOrderedSet<Component> {
  /// Components to be added on the next update.
  ///
  /// The component list is only changed at the start of each update to avoid
  /// concurrency issues.
  final List<Component> _addLater = [];

  /// Components to be removed on the next update.
  ///
  /// The component list is only changed at the start of each update to avoid
  /// concurrency issues.
  final Set<Component> _removeLater = {};

  /// This is the "prepare" function that will be called *before* the
  /// component is added to the component list by the add/addAll methods.
  /// It is also called when the component changes parent.
  final bool Function(Component child) prepare;

  ComponentSet(
    int Function(Component e1, Component e2)? compare,
    this.prepare,
  ) : super(compare);

  /// Prepares and registers one component to be added on the next game tick.
  ///
  /// This is the interface compliant version; if you want to provide an
  /// explicit gameRef or await for the onLoad, use [addChild].
  ///
  /// Note: the component is only added on the next tick. This method always
  /// returns true.
  @override
  bool add(Component c) {
    addChild(c);
    return true;
  }

  /// Prepares and registers a list of components to be added on the next game
  /// tick.
  ///
  /// This is the interface compliant version; if you want to provide an
  /// explicit gameRef or await for the onLoad, use [addChild].
  ///
  /// Note: the components are only added on the next tick. This method always
  /// returns the total lenght of the provided list.
  @override
  int addAll(Iterable<Component> components) {
    addChildren(components);
    return components.length;
  }

  /// Prepares and registers one component to be added on the next game tick.
  ///
  /// This allows you to provide a specific gameRef if this component is being
  /// added from within another component that is already on a BaseGame.
  /// You can await for the onLoad function, if present.
  /// This method can be considered sync for all intents and purposes if no
  /// onLoad is provided by the component.
  Future<void> addChild(Component component) async {
    final isPrepared = prepare(component);
    if (component.parent == null) {
      // Since the components won't be added until a proper game is added
      // further up in the tree we can add them to _addLater and then re-add
      // them once there is a proper root.
      _addLater.add(component);
      return;
    }

    final loadFuture = component.onLoad();
    if (loadFuture != null) {
      await loadFuture;
    }
    await component.children.reAddChildren();

    _addLater.add(component);
  }

  /// Prepares and registers a list of component to be added on the next game
  /// tick.
  ///
  /// See [addChild] for more details.
  Future<void> addChildren(
    Iterable<Component> components, {
    BaseGame? gameRef,
  }) async {
    final ps = components.map(addChild);
    await Future.wait(ps);
  }

  /// The children are removed and then added again to the component set so that
  /// they are prepared and onLoad:ed again. Used when a parent is changed
  /// further up the tree.
  // TODO: Needs to mark the children for removal and then
  Future<void> reAddChildren() async {
    final removedChildren = removeWhere((c) {
      c.onRemove();
      return true;
    })
      ..followedBy(_addLater)
      ..toList(growable: false);
    _addLater.clear();
    Future.wait(removedChildren.map(addChild));
    Future.wait(_addLater.map(addChild));
  }

  /// Marks a component to be removed from the components list on the next game
  /// tick.
  @override
  bool remove(Component c) {
    _removeLater.add(c);
    return true;
  }

  /// Marks a list of components to be removed from the components list on the
  /// next game tick.
  void removeAll(Iterable<Component> components) {
    _removeLater.addAll(components);
  }

  /// Marks all existing components to be removed from the components list on
  /// the next game tick.
  @override
  void clear() {
    _removeLater.addAll(this);
  }

  /// Materializes the component list in reversed order.
  Iterable<Component> reversed() {
    return toList().reversed;
  }

  /// Call this on your update method.
  ///
  /// This method effectuates any pending operations of insertion or removal,
  /// and thus actually modifies the components set.
  /// Note: do not call this while iterating the set.
  void updateComponentList() {
    _removeLater.addAll(where((c) => c.shouldRemove));
    _removeLater.forEach((c) {
      c.onRemove();
      super.remove(c);
      c.shouldRemove = false;
    });
    _removeLater.clear();

    if (_addLater.isNotEmpty) {
      final addNow = _addLater.toList(growable: false);
      _addLater.clear();
      addNow.forEach((c) {
        prepare(c);
        super.add(c);
        c.onMount();
      });
    }
  }

  @override
  void rebalanceAll() {
    final elements = toList();
    // bypass the wrapper because the components are already added
    super.clear();
    elements.forEach(super.add);
  }

  @override
  void rebalanceWhere(bool Function(Component element) test) {
    // bypass the wrapper because the components are already added
    final elements = super.removeWhere(test).toList();
    elements.forEach(super.add);
  }

  /// Creates a [ComponentSet] with a default value for the compare function,
  /// using the Component's priority for sorting.
  ///
  /// You must still provide your [prepare] function depending on the context.
  static ComponentSet createDefault(
    bool Function(Component child) prepare,
  ) {
    return ComponentSet(
      Comparing.on<Component>((c) => c.priority),
      prepare,
    );
  }
}
