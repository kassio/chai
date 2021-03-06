// Chai - Don't let your Mac fall asleep, like a sir
// Copyright (C) 2020 Lorenzo Villani
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Dispatch

//
// Our stuff
//

enum Action {
  case initialize
  case activate(String?)
  case deactivate
  case setDisableAfterSuspendEnabled(Bool)
  case setLoginItemEnabled(Bool)
  case setIsEnabledByDefault(Bool)
}

struct State {
  var active: Bool = false
  var activeItem: ActivationSpec? = nil
  var isDisableAfterSuspendEnabled: Bool = false
  var isLoginItemEnabled: Bool = false
  var isEnabledByDefault: Bool = false
  var lastSession: String? = nil
}

func appReducer(state: State, action: Action) -> State {
  switch action {
  case .initialize:
    let defaults = Defaults()

    var state = State()
    state.isDisableAfterSuspendEnabled = defaults.isDisableAfterSuspendEnabled
    state.isLoginItemEnabled = defaults.isLoginItemEnabled
    state.isEnabledByDefault = defaults.isEnabledByDefault
    state.lastSession = defaults.lastSession
    if let session = defaults.lastSession {
      state.active = true
      state.activeItem = ActivationSpecs.spec(for: session)
    }
    return state
  case .activate(let session):
    Defaults().lastSession = session

    var newState = state
    newState.active = true
    if let session = session {
      newState.lastSession = session
      newState.activeItem = ActivationSpecs.spec(for: session)
    }
    return newState
  case .deactivate:
    Defaults().lastSession = nil

    var newState = state
    newState.active = false
    newState.activeItem = nil
    newState.lastSession = nil
    return newState
  case .setDisableAfterSuspendEnabled(let enabled):
    Defaults().isDisableAfterSuspendEnabled = enabled

    var newState = state
    newState.isDisableAfterSuspendEnabled = enabled
    return newState
  case .setLoginItemEnabled(let enabled):
    Defaults().isLoginItemEnabled = enabled

    var newState = state
    newState.isLoginItemEnabled = enabled
    return newState
  case .setIsEnabledByDefault(let enabled):
    Defaults().isEnabledByDefault = enabled

    var newState = state
    newState.isEnabledByDefault = enabled
    return newState
  }
}

let globalStore = Store(reducer: appReducer, initialState: State())

//
// Infrastructure
//

typealias Reducer = (State, Action) -> State

protocol StoreDelegate: AnyObject {
  func stateChanged(state: State)
}

class Store {
  private let queue = DispatchQueue(label: "StoreDispatchQueue")
  private let reducer: Reducer

  private var _state: State
  private var subscribers: [StoreDelegate] = []

  public var state: State { return queue.sync { _state } }

  public init(reducer: @escaping Reducer, initialState: State) {
    self.reducer = reducer
    self._state = initialState
  }

  public func dispatch(action: Action) {
    queue.sync {
      _state = reducer(_state, action)

      for subscriber in subscribers {
        subscriber.stateChanged(state: _state)
      }
    }
  }

  public func subscribe(storeDelegate: StoreDelegate) {
    queue.sync {
      if !subscribers.contains(where: { $0 === storeDelegate }) {
        subscribers.append(storeDelegate)
        storeDelegate.stateChanged(state: _state)
      }
    }
  }

  public func unsubscribe(storeDelegate: StoreDelegate) {
    queue.sync {
      subscribers.removeAll(where: { $0 === storeDelegate })
    }
  }
}
