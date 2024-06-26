#if canImport(UIKit)

import UIKit
import RxSwift
import RxCocoa

public protocol OutlineNodeType {
    associatedtype NodeType = Self
    var parent: NodeType? { get }
    var children: [NodeType] { get }
}

extension OutlineNodeType {
    public var isExpandable: Bool {
        children.count > 0
    }
}

enum OutlineSection {
    case main
}

@available(iOS 14.0, *)
class OutlineCollectionViewDiffableDataSource<Node: OutlineNodeType & Hashable>: UICollectionViewDiffableDataSource<OutlineSection, Node>, RxCollectionViewDataSourceType, SectionedViewDataSourceType where Node.NodeType == Node {
    typealias ConfigureCell = (UICollectionView, IndexPath, Node, UICollectionViewListCell) -> Void

    typealias Snapshot = NSDiffableDataSourceSectionSnapshot<Node>

    typealias Element = [Node]

    private var currentSnapshot: Snapshot?

    private var filteredSnapshot: Snapshot?

    init(collectionView: UICollectionView, configureCell: @escaping ConfigureCell) {
        let headerCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Node> { cell, indexPath, node in
            configureCell(collectionView, indexPath, node, cell)
            cell.accessories = [.outlineDisclosure(options: .init(style: .header))]
        }

        let listCellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Node> { cell, indexPath, node in
            configureCell(collectionView, indexPath, node, cell)
        }

        super.init(collectionView: collectionView) { collectionView, indexPath, node -> UICollectionViewCell? in
            if node.isExpandable {
                return collectionView.dequeueConfiguredReusableCell(using: headerCellRegistration, for: indexPath, item: node)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: listCellRegistration, for: indexPath, item: node)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, observedEvent event: RxSwift.Event<Element>) {
        Binder(self) { target, nodes in
            let snapshot = target.snapshot(for: nodes)
            target.apply(snapshot, to: .main, animatingDifferences: false)
            target.currentSnapshot = snapshot
        }
        .on(event)
    }

    func collectionView(_ collectionView: UICollectionView, observedFilteredEvent event: RxSwift.Event<Element?>) {
        Binder(self) { target, nodes in
            if let nodes {
                let snapshot = target.snapshot(for: nodes)
                target.apply(snapshot, to: .main, animatingDifferences: false)
                target.filteredSnapshot = snapshot
            } else if let currentSnapshot = target.currentSnapshot {
                target.apply(currentSnapshot, to: .main, animatingDifferences: false)
                target.filteredSnapshot = nil
            }
        }
        .on(event)
    }

    func snapshot(for nodes: [Node]) -> Snapshot {
        var snapshot = Snapshot()
        func addNodes(_ children: [Node], to parent: Node?) {
            snapshot.append(children, to: parent)
            for child in children where child.isExpandable {
                addNodes(child.children, to: child)
            }
        }

        addNodes(nodes, to: nil)
        return snapshot
    }

    func model(at indexPath: IndexPath) throws -> Any {
        precondition(indexPath.section == 0)

        guard let item = itemIdentifier(for: indexPath) else {
            throw RxCocoaError.itemsNotYetBound(object: self)
        }
        return item
    }
}

import OSLog

@available(iOS 14.0, *)
private let logger = Logger(subsystem: "com.JH.RxUIKit", category: "UICollectionView")

@available(iOS 14.0, *)
extension Reactive where Base: UICollectionView {
    public func rootNode<OutlineNode: OutlineNodeType & Hashable, Source: ObservableType>(source: Source)
        -> (@escaping (UICollectionView, IndexPath, OutlineNode, UICollectionViewListCell) -> Void)
        -> Disposable
        where OutlineNode.NodeType == OutlineNode, Source.Element == OutlineNode {
            nodes(source: source.map { [$0] })
    }

    public func nodes<OutlineNode: OutlineNodeType & Hashable, Source: ObservableType>(source: Source)
        -> (@escaping (UICollectionView, IndexPath, OutlineNode, UICollectionViewListCell) -> Void)
        -> Disposable
        where OutlineNode.NodeType == OutlineNode, Source.Element == [OutlineNode] {
        return { cellProvider in
            _ = self.dataSource
            let dataSource = OutlineCollectionViewDiffableDataSource(collectionView: base, configureCell: cellProvider)
            return self.nodes(dataSource: dataSource)(source)
        }
    }

    public func filteredRootNode<OutlineNode: OutlineNodeType & Hashable, Source: ObservableType>(source: Source, outlineNodeType: OutlineNode.Type = OutlineNode.self) -> Disposable where OutlineNode.NodeType == OutlineNode, Source.Element == OutlineNode {
        filteredNodes(source: source.map { [$0] })
    }
    
    public func filteredNodes<OutlineNode: OutlineNodeType & Hashable, Source: ObservableType>(source: Source) -> Disposable where OutlineNode.NodeType == OutlineNode, Source.Element == [OutlineNode] {
        source.subscribe(onNext: { nodes in
            if let outlineDataSource = dataSource.forwardToDelegate() as? OutlineCollectionViewDiffableDataSource<OutlineNode> {
                outlineDataSource.collectionView(base, observedFilteredEvent: .next(nodes))
            } else {
                logger.error("DataSource forwardDelegate must be OutlineCollectionViewDiffableDataSource")
            }
        })
    }

    public func nodes<
        DataSource: RxCollectionViewDataSourceType & UICollectionViewDataSource,
        Source: ObservableType
    >
    (dataSource: DataSource)
        -> (_ source: Source)
        -> Disposable where DataSource.Element == Source.Element {
        return { source in
            // This is called for side effects only, and to make sure delegate proxy is in place when
            // data source is being bound.
            // This is needed because theoretically the data source subscription itself might
            // call `self.rx.delegate`. If that happens, it might cause weird side effects since
            // setting data source will set delegate, and UICollectionView might get into a weird state.
            // Therefore it's better to set delegate proxy first, just to be sure.
            _ = self.delegate
            // Strong reference is needed because data source is in use until result subscription is disposed
            return source.subscribeProxyDataSource(ofObject: self.base, dataSource: dataSource, retainDataSource: true) { [weak collectionView = self.base] (_: RxCollectionViewDataSourceProxy, event) in
                guard let collectionView = collectionView else {
                    return
                }
                dataSource.collectionView(collectionView, observedEvent: event)
            }
        }
    }
}

extension ObservableType {
    func subscribeProxyDataSource<DelegateProxy: DelegateProxyType>(ofObject object: DelegateProxy.ParentObject, dataSource: DelegateProxy.Delegate, retainDataSource: Bool, binding: @escaping (DelegateProxy, Event<Element>) -> Void)
        -> Disposable
        where DelegateProxy.ParentObject: UIView
        , DelegateProxy.Delegate: AnyObject {
        let proxy = DelegateProxy.proxy(for: object)
        let unregisterDelegate = DelegateProxy.installForwardDelegate(dataSource, retainDelegate: retainDataSource, onProxyForObject: object)

        // Do not perform layoutIfNeeded if the object is still not in the view hierarchy
        if object.window != nil {
            // this is needed to flush any delayed old state (https://github.com/RxSwiftCommunity/RxDataSources/pull/75)
            object.layoutIfNeeded()
        }

        let subscription = asObservable()
            .observe(on: MainScheduler())
            .catch { error in
                bindingError(error)
                return Observable.empty()
            }
            // source can never end, otherwise it would release the subscriber, and deallocate the data source
            .concat(Observable.never())
            .take(until: object.rx.deallocated)
            .subscribe { [weak object] (event: Event<Element>) in

                if let object = object {
                    assert(proxy === DelegateProxy.currentDelegate(for: object), "Proxy changed from the time it was first set.\nOriginal: \(proxy)\nExisting: \(String(describing: DelegateProxy.currentDelegate(for: object)))")
                }

                binding(proxy, event)

                switch event {
                case let .error(error):
                    bindingError(error)
                    unregisterDelegate.dispose()
                case .completed:
                    unregisterDelegate.dispose()
                default:
                    break
                }
            }

        return Disposables.create { [weak object] in
            subscription.dispose()

            if object?.window != nil {
                object?.layoutIfNeeded()
            }

            unregisterDelegate.dispose()
        }
    }
}

func bindingError(_ error: Swift.Error) {
    let error = "Binding error: \(error)"
    #if DEBUG
    fatalError(error)
    #else
    print(error)
    #endif
}

extension DelegateProxyType {
    /// Sets forward delegate for `DelegateProxyType` associated with a specific object and return disposable that can be used to unset the forward to delegate.
    /// Using this method will also make sure that potential original object cached selectors are cleared and will report any accidental forward delegate mutations.
    ///
    /// - parameter forwardDelegate: Delegate object to set.
    /// - parameter retainDelegate: Retain `forwardDelegate` while it's being set.
    /// - parameter onProxyForObject: Object that has `delegate` property.
    /// - returns: Disposable object that can be used to clear forward delegate.
    static func installForwardDelegate(_ forwardDelegate: Delegate, retainDelegate: Bool, onProxyForObject object: ParentObject) -> Disposable {
//        weak var weakForwardDelegate: AnyObject? = forwardDelegate as AnyObject
        let proxy = self.proxy(for: object)

//        assert(proxy.forwardToDelegate() === nil, "This is a feature to warn you that there is already a delegate (or data source) set somewhere previously. The action you are trying to perform will clear that delegate (data source) and that means that some of your features that depend on that delegate (data source) being set will likely stop working.\n" +
//            "If you are ok with this, try to set delegate (data source) to `nil` in front of this operation.\n" +
//            " This is the source object value: \(object)\n" +
//            " This is the original delegate (data source) value: \(proxy.forwardToDelegate()!)\n" +
//            "Hint: Maybe delegate was already set in xib or storyboard and now it's being overwritten in code.\n")

        proxy.setForwardToDelegate(forwardDelegate, retainDelegate: retainDelegate)

        return Disposables.create {
            MainScheduler.ensureRunningOnMainThread()

//            let delegate: AnyObject? = weakForwardDelegate

//            assert(delegate == nil || proxy.forwardToDelegate() === delegate, "Delegate was changed from time it was first set. Current \(String(describing: proxy.forwardToDelegate())), and it should have been \(proxy)")

            proxy.setForwardToDelegate(nil, retainDelegate: retainDelegate)
        }
    }
}

#endif
