//
//  File.swift
//
//
//  Created by 細沼祐介 on 2022/03/04.
//

import Auth
import Combine
import Core
import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct ProposalListContainerView: View {
    @EnvironmentObject var viewModel: ProposalListViewModel

    // ⚠️ Bug
    //
    // [macOS]
    // Initialized each time like @ObservedObject.
    // https://stackoverflow.com/questions/71345489/swiftui-macos-navigationview-onchangeof-bool-action-tried-to-update-multipl
    //
    // [iOS]
    // Double generated with View.
    // https://developer.apple.com/forums/thread/655159
    //
    // @StateObject var viewModel: ProposalListViewModel = .init(globalFilter: Filter.filter)

    public init() {}

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case .error:
                VStack {
                    Text("Network error")
                    Button("Retry") {
                        Task {
                            await viewModel.onTapRetry()
                        }
                    }
                    .padding()
                }
            case let .success(content):
                contentView(content)
            }
        }
        .alert("Network Error", isPresented: $viewModel.isPresentNetworkErrorAlert) {}
        .sheet(isPresented: $viewModel.isPresentAuthView) {
            LoginView()
        }
        .task {
            await viewModel.onAppear()
        }
    }

    func contentView(_ content: ProposalListViewModel.Content) -> some View {
        // FIXME: キーボードでエンターして確定するとキーワードが消えちゃう（謎）

        ProposalListView(proposals: content.filteredProposals) { proposal in
            Task {
                await viewModel.onTapStar(proposal: proposal)
            }
        }
        .refreshable {
            await viewModel.onRefresh()
        }
        .searchable(
            text: Binding(get: { content.searchQuery }, set: { viewModel.onChangeQuery($0) }),
            placement: .automatic,
            prompt: Text("Search Proposal"),
            suggestions: {
                ForEach(content.suggestions, id: \.0.self) { title, completion in
                    Text(title).searchCompletion(completion)
                }
            }
        )
        .onSubmit(of: .search) {
            // Do something if needed.
        }
    }
}

@MainActor
public final class ProposalListViewModel: ObservableObject {
    @Published var state: State = .loading
    @Published var isPresentNetworkErrorAlert = false
    @Published var isPresentAuthView = false

    enum State: Equatable {
        case loading
        case error
        case success(Content)
    }

    struct Content: Equatable {
        var allProposals: [Proposal] // For data-source
        var searchQuery: String = ""

        init(proposals: [Proposal]) {
            allProposals = proposals
        }

        var filteredProposals: [Proposal] {
            allProposals.search(by: searchQuery)
        }

        var suggestions: [(String, String)] {
            allProposals.suggestions(query: searchQuery)
        }
    }

    private let globalFilter: (Proposal) -> Bool
    private var dataSource: ProposalDataSource
    private var authState: AuthState

    #if os(iOS)
    private var feedbackGenerator: UIImpactFeedbackGenerator!
    #endif

    private var cancellable: Set<AnyCancellable> = []

    public nonisolated init(
        globalFilter: @escaping (Proposal) -> Bool,
        authState: AuthState,
        dataSource: ProposalDataSource
    ) {
        self.globalFilter = globalFilter
        self.authState = authState
        self.dataSource = dataSource
    }

    // MARK: Lifecycle

    lazy var initialize: () = {
        #if os(iOS)
        feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        #endif
        dataSource.proposals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] proposals in
                guard let self = self else { return }

                guard let proposals = proposals else {
                    self.state = .error
                    return
                }

                if proposals.isEmpty {
                    self.state = .loading
                } else {
                    if case var .success(content) = self.state {
                        content.allProposals = proposals.filter(self.globalFilter)
                        self.state = .success(content)
                    } else {
                        self.state = .success(
                            Content(
                                proposals: proposals.filter(self.globalFilter)
                            )
                        )
                    }
                }
            }
            .store(in: &cancellable)
    }()

    func onAppear() async {
        _ = initialize
        #if os(iOS)
        feedbackGenerator.prepare()
        #endif
    }

    // MARK: Actions - Success

    func onChangeQuery(_ query: String) {
        guard case var .success(content) = state else { return }

        content.searchQuery = query
        state = .success(content)
    }

    func onTapStar(proposal: Proposal) async {
        if let _ = authState.user {
            #if os(iOS)
            feedbackGenerator.impactOccurred()
            #endif
            await dataSource.toggleStar(proposal: proposal)
        } else {
            isPresentAuthView = true
        }
    }

    func onRefresh() async {
        do {
            // Note:
            // Wait at least 1 seconds. (for UX)
            async let wait1: () = try Task.sleep(seconds: 1)
            async let wait2: () = try dataSource.refresh()
            let _ = try await (wait1, wait2)
        } catch {
            isPresentNetworkErrorAlert = true
        }
    }

    // MARK: Actions - Error

    func onTapRetry() async {
        state = .loading
        do {
            try await dataSource.refresh()
        } catch {
            state = .error
        }
    }
}

// protocol ProposalFilter {
//    static func filter(entity: Proposal) -> Bool
// }
//
// enum NoFilter: ProposalFilter {
//    static func filter(entity: Proposal) -> Bool {
//        true
//    }
// }
//
// enum StaredFilter: ProposalFilter {
//    static func filter(entity: Proposal) -> Bool {
//        entity.star
//    }
// }
