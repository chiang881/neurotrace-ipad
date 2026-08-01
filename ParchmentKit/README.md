# ParchmentKit

The local package defines the replaceable application boundaries used by the iPad app:

- `ParchmentDomain`: immutable research snapshots and export contract.
- `ParchmentApplication`: repository, analysis, export and settings protocols.
- `ParchmentInfrastructure`: V2 persistence and file-layout constants.
- `ParchmentUIKit`: UIKit-only presentation policy.

`ParchmentDomain` and `ParchmentApplication` do not import UIKit. The UIKit product does not import SwiftData, Core ML or Foundation Networking.
