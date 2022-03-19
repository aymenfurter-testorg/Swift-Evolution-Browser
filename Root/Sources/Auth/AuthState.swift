//
//  File.swift
//
//
//  Created by 細沼祐介 on 2022/03/06.
//

import Combine
import Core
import FirebaseAuth
import Foundation

public final class AuthState: ObservableObject {
    @Published public var user: Account? = nil
    @Published public var isLogin: Bool = false

    private var handle: AuthStateDidChangeListenerHandle!

    public init() {
        handle = Auth.auth().addStateDidChangeListener { _, user in
            self.user = user.map { Account(uid: $0.uid, name: $0.displayName ?? "") }
            self.isLogin = user != nil
        }
    }

    deinit {
        Auth.auth().removeStateDidChangeListener(handle)
    }

    public func logout() {
        do {
            try Auth.auth().signOut()
        } catch {
            preconditionFailure("\(error)")
        }
    }

    public func authedPublisher<Output>(
        _ innerPublisher: @escaping (Account) -> AnyPublisher<Output, Never>,
        defaultValue: Output
    ) -> AnyPublisher<Output, Never> {
        $user
            .flatMap { user -> AnyPublisher<Output, Never> in
                if let user = user {
                    return innerPublisher(user)
                } else {
                    return Just(defaultValue).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
}
