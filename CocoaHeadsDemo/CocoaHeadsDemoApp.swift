import GRDB
import GRDBQuery
import Combine
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
    var id: Int64?
    var name: String
    var score: Int
}

extension Player: Codable, FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let name = Column(CodingKeys.name)
        static let score = Column(CodingKeys.score)
    }
    
    mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}

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
    private let dbWriter: DatabaseWriter
    
    init(dbWriter: DatabaseWriter) {
        self.dbWriter = dbWriter
        try! databaseMigrator.migrate(dbWriter)
    }
    
    private var databaseMigrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("players") { db in
            try db.create(table: "player") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("score", .integer).notNull()
            }
        }
        return migrator
    }
    
    // MARK: - Database Access
    
    func insertPlayer(_ player: Player) throws {
        try dbWriter.write { db in
            var player = player
            try player.insert(db)
        }
    }
    
    func deleteAllPlayers() throws {
        try dbWriter.write { db in
            _ = try Player.deleteAll(db)
        }
    }
    
    func playersPublisher(ordering: Player.Ordering) -> AnyPublisher<[Player], Error> {
        ValueObservation
            .tracking(Player.order(ordering).fetchAll)
            .publisher(in: dbWriter, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}

// MARK: - SwiftUI Environment

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
    @Environment(\.playerStore) var playerStore
    
    @Query(PlayerListRequest(ordering: .byScore), in: \.playerStore)
    var players: [Player]
    
    var body: some View {
        NavigationView {
            List(players) { player in
                HStack {
                    Text(player.name)
                    Spacer()
                    Text("\(player.score) points")
                }
            }
            .animation(.default, value: players)
            .navigationTitle("\(players.count) Players")
            .toolbar {
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
                Label("Score", systemImage: "arrowtriangle.down.fill").labelStyle(.titleAndIcon)
            }
        case .byName:
            Button {
                ordering = .byScore
            } label: {
                Label("Name", systemImage: "arrowtriangle.up.fill").labelStyle(.titleAndIcon)
            }
        }
    }
}

// MARK: - PlayerListRequest

struct PlayerListRequest {
    var ordering: Player.Ordering
}

extension PlayerListRequest: Queryable {
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
    
    /// Creates a new player with random name and random score
    static func makeRandom() -> Player {
        Player(
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
