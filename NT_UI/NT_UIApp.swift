//
//  NT_UIApp.swift
//  NT_UI
//
//  Created by 蒋棕基 on 2026/5/27.
//

import SwiftData
import SwiftUI

@main
struct NT_UIApp: App {
    private let modelContainer: ModelContainer
    @State private var services = AppServices()

    init() {
        let schema = Schema([
            Subject.self,
            TestSession.self,
            TaskRecord.self
        ])
        let configuration = ModelConfiguration(
            "Parchment",
            schema: schema,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("无法创建羊皮纸数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(services)
        }
        .modelContainer(modelContainer)
    }
}
