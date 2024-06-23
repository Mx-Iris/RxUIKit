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
    
    typealias Element = [Node]
    
    func collectionView(_ collectionView: UICollectionView, observedEvent: RxSwift.Event<Element>) {
        Binder(self) { target, nodes in
            var snapshot = NSDiffableDataSourceSectionSnapshot<Node>()
            func addNodes(_ children: [Node], to parent: Node?) {
                snapshot.append(children, to: parent)
                for child in children where child.isExpandable {
                    addNodes(child.children, to: child)
                }
            }

            addNodes(nodes, to: nil)
            target.apply(snapshot, to: .main, animatingDifferences: false)
        }
        .on(observedEvent)
    }

    
    func model(at indexPath: IndexPath) throws -> Any {
        precondition(indexPath.section == 0)
        
        guard let item = itemIdentifier(for: indexPath) else {
            throw RxCocoaError.itemsNotYetBound(object: self)
        }
        return item
    }
}

extension Reactive where Base: UICollectionView {
    
    @available(iOS 14.0, *)
    public func rootNode<OutlineNode: OutlineNodeType & Hashable, Source: ObservableType>(source: Source)
        -> (@escaping (UICollectionView, IndexPath, OutlineNode) -> UICollectionViewCell?)
        -> Disposable
        where OutlineNode.NodeType == OutlineNode, Source.Element == OutlineNode {
        return { cellProvider in
            let dataSource = OutlineCollectionViewDiffableDataSource(collectionView: base, cellProvider: cellProvider)
            return self.items(dataSource: dataSource)(source.map { [$0] })
        }
    }
    
    @available(iOS 14.0, *)
    public func nodes<OutlineNode: OutlineNodeType & Hashable, Source: ObservableType>(source: Source)
        -> (@escaping (UICollectionView, IndexPath, OutlineNode) -> UICollectionViewCell?)
        -> Disposable
        where OutlineNode.NodeType == OutlineNode, Source.Element == [OutlineNode] {
        return { cellProvider in
            let dataSource = OutlineCollectionViewDiffableDataSource(collectionView: base, cellProvider: cellProvider)
            return self.items(dataSource: dataSource)(source)
        }
    }
}

#endif
