# NeuroTraceKit

The local package defines the replaceable application boundaries used by the iPad app:

- `NeuroTraceDomain`: immutable research snapshots and export contract.
- `NeuroTraceApplication`: repository, analysis, export and settings protocols.
- `NeuroTraceInfrastructure`: V2 persistence and file-layout constants.
- `NeuroTraceUIKit`: UIKit-only presentation policy.

`NeuroTraceDomain` and `NeuroTraceApplication` do not import UIKit. The UIKit product does not import SwiftData, Core ML or Foundation Networking.
