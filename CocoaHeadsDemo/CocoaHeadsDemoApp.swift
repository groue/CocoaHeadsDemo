import Combine
import GRDB
import GRDBQuery
import SwiftUI

@main
struct CocoaHeadsDemoApp: App {
    var body: some Scene {
        WindowGroup {
            PlayerListView()
        }
    }
}

// MARK: - Player

struct Player: Equatable, Identifiable {
    var id: UUID
    var name: String
    var score: Int
}

/// Add database powers
/// <https://github.com/groue/GRDB.swift/blob/master/README.md#records>
extension Player: Codable, FetchableRecord, PersistableRecord {
    enum Columns {
        static let name = Column(CodingKeys.name)
        static let score = Column(CodingKeys.score)
    }
}

/// Define database requests
/// <https://github.com/groue/GRDB.swift/blob/master/README.md#requests>
extension Player {
    enum Ordering { case byName, byScore }
    
    static func order(_ ordering: Ordering) -> QueryInterfaceRequest<Player> {
        switch ordering {
        case .byScore:
            return order(Columns.score.desc)
        case .byName:
            return order(Columns.name.collating(.localizedStandardCompare))
        }
    }
}

// MARK: - PlayerStore

final class PlayerStore {
    /// The database connection
    /// <https://github.com/groue/GRDB.swift/blob/master/README.md#database-connections>
    private let dbWriter: DatabaseWriter
    
    init(dbWriter: DatabaseWriter) {
        self.dbWriter = dbWriter
        try! databaseMigrator.migrate(dbWriter)
    }
    
    /// Define database migrations
    /// <https://github.com/groue/GRDB.swift/blob/master/Documentation/Migrations.md>
    private var databaseMigrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("players") { db in
            try db.create(table: "player") { t in
                t.column("id", .blob).notNull().primaryKey()
                t.column("name", .text).notNull()
                t.column("score", .integer).notNull()
            }
        }
        
        return migrator
    }
}

// MARK: - PlayerStore: Database Access

extension PlayerStore {
    func insertPlayer(_ player: Player) throws {
        try dbWriter.write { db in
            try player.insert(db)
        }
    }
    
    func deleteAllPlayers() throws {
        try dbWriter.write { db in
            _ = try Player.deleteAll(db)
        }
    }
    
    /// Observes the database
    /// <https://github.com/groue/GRDB.swift/blob/master/README.md#valueobservation>
    func playersPublisher(ordering: Player.Ordering) -> AnyPublisher<[Player], Error> {
        ValueObservation
            .tracking { db in
                try Player.order(ordering).fetchAll(db)
            }
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}

// MARK: - SwiftUI Environment

/// A SwiftUI environment key for the PlayerStore
/// <https://developer.apple.com/documentation/swiftui/environmentkey>
private struct PlayerStoreKey: EnvironmentKey {
    static let defaultValue = PlayerStore.makeDemoStore(count: 4)
}

extension EnvironmentValues {
    var playerStore: PlayerStore {
        get { self[PlayerStoreKey.self] }
        set { self[PlayerStoreKey.self] = newValue }
    }
}

// MARK: - PlayerListView

struct PlayerListView: View {
    /// Provides write access
    @Environment(\.playerStore) var playerStore
    
    /// Always up-to-date list of players
    /// <http://github.com/groue/GRDBQuery>
    @Query(PlayerListRequest(), in: \.playerStore)
    var players: [Player]
    
    var body: some View {
        NavigationView {
            playerList
            .toolbar { toolbarContent }
            .navigationTitle("\(players.count) Players")
        }
    }
}

extension PlayerListView {
    private var playerList: some View {
        List(players) { player in
            HStack {
                Text(player.name)
                Spacer()
                Text("\(player.score) points")
            }
        }
        .animation(.default, value: players)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            ToggleOrderingButton(ordering: $players.ordering)
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                try! playerStore.deleteAllPlayers()
            } label: { Image(systemName: "trash") }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                try! playerStore.insertPlayer(Player.makeRandom())
            } label: { Image(systemName: "plus") }
        }
    }
}

struct ToggleOrderingButton: View {
    @Binding var ordering: Player.Ordering
    
    var body: some View {
        switch ordering {
        case .byScore:
            Button {
                ordering = .byName
            } label: {
                Label("Score", systemImage: "arrowtriangle.down.fill")
                    .labelStyle(.titleAndIcon)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        case .byName:
            Button {
                ordering = .byScore
            } label: {
                Label("Name", systemImage: "arrowtriangle.up.fill")
                    .labelStyle(.titleAndIcon)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
}

// MARK: - PlayerListRequest

/// Feeds SwiftUI views with the list of players
/// <http://github.com/groue/GRDBQuery>
struct PlayerListRequest: Queryable {
    /// The ordering of the list
    var ordering: Player.Ordering = .byScore
    
    static var defaultValue: [Player] { [] }
    
    func publisher(in playerStore: PlayerStore) -> AnyPublisher<[Player], Error> {
        playerStore.playersPublisher(ordering: ordering)
    }
}

// MARK: - Demo Support

extension Player {
    private static let names = [
        "Arthur", "Anita", "Barbara", "Bernard", "Craig", "Chiara", "David",
        "Dean", "Éric", "Elena", "Fatima", "Frederik", "Gilbert", "Georgette",
        "Henriette", "Hassan", "Ignacio", "Irene", "Julie", "Jack", "Karl",
        "Kristel", "Louis", "Liz", "Masashi", "Mary", "Noam", "Nicole",
        "Ophelie", "Oleg", "Pascal", "Patricia", "Quentin", "Quinn", "Raoul",
        "Rachel", "Stephan", "Susie", "Tristan", "Tatiana", "Ursule", "Urbain",
        "Victor", "Violette", "Wilfried", "Wilhelmina", "Yvon", "Yann",
        "Zazie", "Zoé"]
    
    static func makeRandom() -> Player {
        Player(
            id: UUID(),
            name: names.randomElement()!,
            score: 10 * Int.random(in: 0...100))
    }
}

extension PlayerStore {
    static func makeDemoStore(count: Int) -> PlayerStore {
        let playerStore = PlayerStore(dbWriter: DatabaseQueue())
        for _ in 0..<count {
            try! playerStore.insertPlayer(Player.makeRandom())
        }
        return playerStore
    }
}

struct PlayerListView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerListView().environment(\.playerStore, .makeDemoStore(count: 4))
        PlayerListView().environment(\.playerStore, .makeDemoStore(count: 0))
        PlayerListView().environment(\.playerStore, .makeDemoStore(count: 100))
    }
}
