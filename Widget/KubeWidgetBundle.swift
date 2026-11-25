import SwiftUI
import WidgetKit

@main
struct KubeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClustersWidget()
        ClusterWidget()
        NamespaceWidget()
        SSHWidget()
    }
}
