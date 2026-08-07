import Foundation

struct SystemCommand: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case sleep
        case sleepDisplays = "sleep-displays"
        case restart
        case shutDown = "shut-down"
        case logOut = "log-out"
        case showScreenSaver = "show-screen-saver"
        case playPause = "play-pause"
        case nextTrack = "next-track"
        case previousTrack = "previous-track"
        case toggleMute = "toggle-mute"
        case volumeUp = "volume-up"
        case volumeDown = "volume-down"
        case showDesktop = "show-desktop"
        case toggleAppearance = "toggle-system-appearance"
        case openTrash = "open-trash"
        case emptyTrash = "empty-trash"
        case ejectAllDisks = "eject-all-disks"
        case toggleHiddenFiles = "toggle-hidden-files"
        case hideOtherApps = "hide-all-apps-except-frontmost"
        case unhideAllApps = "unhide-all-hidden-apps"
        case quitAllApps = "quit-all-apps"
    }

    enum Confirmation: Sendable, Equatable {
        case none
        case required
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let confirmation: Confirmation

    var entryID: String {
        id == .quitAllApps ? "command:quit-all-apps" : "system-command:" + id.rawValue
    }
}

enum SystemCommandCatalog {
    static let all: [SystemCommand] = SystemCommand.ID.allCases.map { id in
        SystemCommand(
            id: id,
            name: name(for: id),
            sfSymbol: symbol(for: id),
            confirmation: confirmation(for: id)
        )
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })

    static func command(forEntryID entryID: String) -> SystemCommand? {
        byEntryID[entryID]
    }

    private static func name(for id: SystemCommand.ID) -> String {
        switch id {
        case .sleep: return "Sleep"
        case .sleepDisplays: return "Sleep Displays"
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        case .logOut: return "Log Out"
        case .showScreenSaver: return "Show Screen Saver"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .toggleMute: return "Toggle Mute"
        case .volumeUp: return "Turn Volume Up"
        case .volumeDown: return "Turn Volume Down"
        case .showDesktop: return "Show Desktop"
        case .toggleAppearance: return "Toggle System Appearance"
        case .openTrash: return "Open Trash"
        case .emptyTrash: return "Empty Trash"
        case .ejectAllDisks: return "Eject All Disks"
        case .toggleHiddenFiles: return "Toggle Hidden Files"
        case .hideOtherApps: return "Hide All Apps Except Frontmost"
        case .unhideAllApps: return "Unhide All Hidden Apps"
        case .quitAllApps: return "Quit All Applications"
        }
    }

    private static func symbol(for id: SystemCommand.ID) -> String {
        switch id {
        case .sleep: return "moon.zzz"
        case .sleepDisplays: return "display"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .showScreenSaver: return "rectangle.inset.filled"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        case .toggleMute: return "speaker.slash"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .showDesktop: return "macwindow.on.rectangle"
        case .toggleAppearance: return "circle.lefthalf.filled"
        case .openTrash: return "trash"
        case .emptyTrash: return "trash.slash"
        case .ejectAllDisks: return "externaldrive"
        case .toggleHiddenFiles: return "eye.slash"
        case .hideOtherApps: return "eye.slash.circle"
        case .unhideAllApps: return "eye.circle"
        case .quitAllApps: return "xmark.circle"
        }
    }

    private static func confirmation(for id: SystemCommand.ID) -> SystemCommand.Confirmation {
        switch id {
        case .restart, .shutDown, .logOut, .emptyTrash, .ejectAllDisks, .quitAllApps:
            return .required
        default:
            return .none
        }
    }
}
