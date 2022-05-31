import Combine
import GRDB
import GRDBQuery
import SwiftUI

@main
struct CocoaHeadsDemoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                PlayerListView().tabItem {
                    Label("Players", systemImage: "person.3.sequence")
                }
                StatisticsView().tabItem {
                    Label("Statistics", systemImage: "chart.pie")
                }
            }
        }
    }
}

// MARK: - Model Player

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

// MARK: - Model Statistics

struct Statistics {
    var numberOfPlayers: Int
    var maximumScore: Int?
    var medianScore: Int?
    var minimumScore: Int?
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

// MARK: PlayerStore: Writes

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
}

// MARK: PlayerStore: Reads

extension PlayerStore {
    /// Observes the list of players in the database
    /// <https://github.com/groue/GRDB.swift/blob/master/README.md#valueobservation>
    func publishPlayers(ordering: Player.Ordering)
    -> AnyPublisher<[Player], Error>
    {
        ValueObservation.tracking { db in
            try Player.order(ordering).fetchAll(db)
        }
        .publisher(in: dbWriter, scheduling: .immediate)
        .eraseToAnyPublisher()
    }
    
    /// Observes the player statistics
    func publishStatistics()
    -> AnyPublisher<Statistics, Error>
    {
        ValueObservation.tracking { db in
            let numberOfPlayers = try Player.fetchCount(db)
            
            let maximumScore = try Player
                .select(max(Player.Columns.score), as: Int.self)
                .fetchOne(db)
            
            let minimumScore = try Player
                .select(min(Player.Columns.score), as: Int.self)
                .fetchOne(db)
            
            let medianScore = try SQLRequest<Int>("""
                SELECT AVG(score)
                FROM (SELECT score
                      FROM player
                      ORDER BY score
                      LIMIT 2 - (SELECT COUNT(*) FROM player) % 2
                      OFFSET (SELECT (COUNT(*) - 1) / 2 FROM player))
                """).fetchOne(db)
            
            return Statistics(
                numberOfPlayers: numberOfPlayers,
                maximumScore: maximumScore,
                medianScore: medianScore,
                minimumScore: minimumScore)
        }
        .publisher(in: dbWriter, scheduling: .immediate)
        .eraseToAnyPublisher()
    }
}

// MARK: - SwiftUI Environment

/// A SwiftUI environment key for the PlayerStore
/// <https://developer.apple.com/documentation/swiftui/environmentkey>
private struct PlayerStoreKey: EnvironmentKey {
    static let defaultValue = PlayerStore.makeDemoStore(playerCount: 4)
}

extension EnvironmentValues {
    var playerStore: PlayerStore {
        get { self[PlayerStoreKey.self] }
        set { self[PlayerStoreKey.self] = newValue }
    }
}

// MARK: - PlayerListView

struct PlayerListView: View {
    /// Always up-to-date list of players
    /// <http://github.com/groue/GRDBQuery>
    @Query(PlayerListRequest(), in: \.playerStore)
    var players: [Player]
    
    var body: some View {
        NavigationView {
            List(players) { player in
                HStack {
                    Text(player.name)
                    Spacer()
                    Text("\(player.score) points").foregroundStyle(.secondary)
                }
            }
            .animation(.default, value: players)
            .toolbar { PlayerListToolbar(ordering: $players.ordering) }
            .navigationTitle("\(players.count) Players")
        }
    }
}

/// The toolbar for the list of players
struct PlayerListToolbar: ToolbarContent {
    @Binding var ordering: Player.Ordering
    
    /// Provides write access
    @Environment(\.playerStore) var playerStore
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
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

/// Feeds SwiftUI views with the list of players
/// <http://github.com/groue/GRDBQuery>
struct PlayerListRequest: Queryable {
    static let defaultValue: [Player] = []
    var ordering = Player.Ordering.byScore
    
    func publisher(in playerStore: PlayerStore)
    -> AnyPublisher<[Player], Error>
    {
        playerStore.publishPlayers(ordering: ordering)
    }
}

// MARK: - StatisticsView

final class StatisticsViewModel: ObservableObject {
    @Published var statistics = Statistics(numberOfPlayers: 0)
    
    private let playerStore: PlayerStore
    private var cancellable: AnyCancellable?
    
    init(playerStore: PlayerStore) {
        self.playerStore = playerStore
        self.cancellable = playerStore.publishStatistics().sink(
            receiveCompletion: { _ in },
            receiveValue: { [weak self] statistics in
                self?.statistics = statistics
            })
    }
    
    func deleteAllPlayers() {
        try! playerStore.deleteAllPlayers()
    }
    
    func insertPlayer() {
        try! playerStore.insertPlayer(Player.makeRandom())
    }
}

struct StatisticsView: View {
    /// This demo uses the SwiftUI environment as a Dependency Injection container
    @Environment(\.playerStore) var playerStore
    
    var body: some View {
        NavigationView {
            ContentView(playerStore: playerStore)
        }
    }
    
    private struct ContentView: View {
        /// A view model
        @StateObject var viewModel: StatisticsViewModel
        
        init(playerStore: PlayerStore) {
            // Inject the playerStore in the @StateObject view model
            _viewModel = StateObject(wrappedValue: .init(playerStore: playerStore))
        }
        
        var body: some View {
            List {
                Section {
                    HStack {
                        Text("Number of players")
                        Spacer()
                        Text("\(viewModel.statistics.numberOfPlayers)")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack {
                        Image(systemName: "arrow.up.to.line")
                        Text("Maximum score")
                        Spacer()
                        Text(viewModel.statistics.maximumScore.map { "\($0) points" } ?? "-")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "arrow.up.and.down")
                        Text("Median score")
                        Spacer()
                        Text(viewModel.statistics.medianScore.map { "\($0) points" } ?? "-")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "arrow.down.to.line")
                        Text("Minimum score")
                        Spacer()
                        Text(viewModel.statistics.minimumScore.map { "\($0) points" } ?? "-")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.deleteAllPlayers()
                    } label: { Image(systemName: "trash") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.insertPlayer()
                    } label: { Image(systemName: "plus") }
                }
            }
            .navigationTitle("Statistics")
        }
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
    static func makeDemoStore(playerCount: Int) -> PlayerStore {
        let inMemoryDatabase = DatabaseQueue()
        let playerStore = PlayerStore(dbWriter: inMemoryDatabase)
        for _ in 0..<playerCount {
            try! playerStore.insertPlayer(Player.makeRandom())
        }
        return playerStore
    }
}

// MARK: - Previews

struct PlayerListView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerListView().environment(\.playerStore, .makeDemoStore(playerCount: 4))
        PlayerListView().environment(\.playerStore, .makeDemoStore(playerCount: 0))
        PlayerListView().environment(\.playerStore, .makeDemoStore(playerCount: 100))
    }
}

struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        StatisticsView().environment(\.playerStore, .makeDemoStore(playerCount: 4))
        StatisticsView().environment(\.playerStore, .makeDemoStore(playerCount: 0))
        StatisticsView().environment(\.playerStore, .makeDemoStore(playerCount: 100))
    }
}
