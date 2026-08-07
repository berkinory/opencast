import Foundation

struct ExtensionManifest: Codable, Sendable {
    let schemaVersion: Int
    let name: String
    let title: String
    let description: String
    let author: String?
    let license: String?
    let preferences: [ExtensionManifestPreference]?
    let commands: [ExtensionManifestCommand]
}

struct ExtensionManifestPreference: Codable, Hashable, Sendable {
    let name: String
    let title: String
    let description: String?
    let type: String
    let required: Bool
    let defaultValue: String?
    let options: [ExtensionPreferenceOption]

    enum CodingKeys: String, CodingKey {
        case name, title, description, type, required
        case defaultValue = "default"
        case options = "data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? name
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "textfield"
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        if let value = try container.decodeIfPresent(String.self, forKey: .defaultValue) {
            defaultValue = value
        } else if let value = try container.decodeIfPresent(Bool.self, forKey: .defaultValue) {
            defaultValue = value ? "true" : "false"
        } else if let value = try container.decodeIfPresent(Double.self, forKey: .defaultValue) {
            defaultValue = String(value)
        } else {
            defaultValue = nil
        }
        options =
            try container.decodeIfPresent([ExtensionPreferenceOption].self, forKey: .options) ?? []
    }
}

struct ExtensionPreferenceOption: Codable, Hashable, Sendable {
    let title: String
    let value: String

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            title = string
            value = string
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title) {
            title = decodedTitle
        } else if let decodedLabel = try container.decodeIfPresent(String.self, forKey: .label) {
            title = decodedLabel
        } else {
            title = try container.decode(String.self, forKey: .value)
        }
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? title
    }

    private enum CodingKeys: String, CodingKey { case title, label, value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(value, forKey: .value)
    }
}

struct ExtensionManifestCommand: Codable, Sendable {
    let name: String
    let title: String
    let subtitle: String?
    let icon: String?
    let entry: String
    let mode: String
    let interval: String?
    let menuBar: Bool?
    let capabilities: [String]?
    let networkDomains: [String]?
    let executables: [String]?
    let filesystemRoots: [String]?
    let shell: Bool?
    let preferences: [ExtensionManifestPreference]?
}

struct ExtensionCommand: Identifiable, Hashable, Sendable {
    let id: String
    let extensionName: String
    let title: String
    let subtitle: String?
    let icon: String?
    let description: String
    let mode: String
    let capabilities: [String]
    let interval: String?
    let menuBar: Bool
    let networkDomains: [String]
    let executables: [String]
    let filesystemRoots: [String]
    let shell: Bool
    let preferences: [ExtensionManifestPreference]
    let bundleURL: URL

    var entryName: String { id }

    init(id: String, title: String, subtitle: String?, bundleID: String) {
        self.id = id
        extensionName = bundleID
        self.title = title
        self.subtitle = subtitle
        icon = nil
        description = ""
        mode = "view"
        capabilities = []
        interval = nil
        menuBar = false
        networkDomains = []
        executables = []
        filesystemRoots = []
        shell = false
        preferences = []
        bundleURL = URL(fileURLWithPath: "")
    }

    init(manifest: ExtensionManifest, command: ExtensionManifestCommand, bundleURL: URL) {
        id = "extension:\(manifest.name):\(command.name)"
        extensionName = manifest.name
        title = command.title
        subtitle = command.subtitle
        icon = command.icon
        description = manifest.description
        mode = command.mode
        capabilities = command.capabilities ?? []
        interval = command.interval
        menuBar = command.menuBar ?? false
        networkDomains = command.networkDomains ?? []
        executables = command.executables ?? []
        filesystemRoots = command.filesystemRoots ?? []
        shell = command.shell ?? false
        preferences = command.preferences ?? manifest.preferences ?? []
        self.bundleURL = bundleURL
    }
}

struct ExtensionRuntimeMetrics: Codable, Equatable, Sendable {
    let commandID: String
    let durationMS: Int
    let peakResidentBytes: Int?
    let reason: String
    let timestamp: Date
}

struct ExtensionFeedback: Equatable, Sendable, Identifiable {
    let id: String
    let kind: String
    let title: String?
    let message: String?
    let style: String?
}

struct ExtensionMenuBarSnapshot: Codable, Equatable, Identifiable, Sendable {
    let commandID: String
    let title: String
    let subtitle: String?
    let snapshot: ExtensionRenderSnapshot
    let updatedAt: Date
    let staleAfterSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case commandID, title, subtitle, snapshot, updatedAt, staleAfterSeconds
    }

    init(
        commandID: String, title: String, subtitle: String?, snapshot: ExtensionRenderSnapshot,
        updatedAt: Date, staleAfterSeconds: Double? = nil
    ) {
        self.commandID = commandID
        self.title = title
        self.subtitle = subtitle
        self.snapshot = snapshot
        self.updatedAt = updatedAt
        self.staleAfterSeconds = staleAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandID = try container.decode(String.self, forKey: .commandID)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        snapshot = try container.decode(ExtensionRenderSnapshot.self, forKey: .snapshot)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        staleAfterSeconds = try container.decodeIfPresent(Double.self, forKey: .staleAfterSeconds)
    }

    var isStale: Bool {
        guard let staleAfterSeconds else { return false }
        return Date().timeIntervalSince(updatedAt) > staleAfterSeconds
    }

    var id: String { commandID }
}

struct ExtensionRenderSnapshot: Codable, Equatable, Sendable {
    let root: String
    let items: [ExtensionRenderItem]
    let actions: [ExtensionRenderAction]
    let fields: [ExtensionRenderField]
    let detail: ExtensionRenderDetail?
    let selectedItemID: String?
    let loading: Bool
    let listDropdown: ExtensionListDropdown?
    let emptyView: ExtensionRenderEmptyView?
    let pagination: ExtensionRenderPagination?
    let searchBarPlaceholder: String?
    let filtering: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        root = try container.decode(String.self, forKey: .root)
        items = try container.decodeIfPresent([ExtensionRenderItem].self, forKey: .items) ?? []
        actions = try container.decodeIfPresent([ExtensionRenderAction].self, forKey: .actions) ?? []
        fields = try container.decodeIfPresent([ExtensionRenderField].self, forKey: .fields) ?? []
        detail = try container.decodeIfPresent(ExtensionRenderDetail.self, forKey: .detail)
        selectedItemID = try container.decodeIfPresent(String.self, forKey: .selectedItemID)
        loading = try container.decodeIfPresent(Bool.self, forKey: .loading) ?? false
        listDropdown = try container.decodeIfPresent(ExtensionListDropdown.self, forKey: .listDropdown)
        emptyView = try container.decodeIfPresent(ExtensionRenderEmptyView.self, forKey: .emptyView)
        pagination = try container.decodeIfPresent(ExtensionRenderPagination.self, forKey: .pagination)
        searchBarPlaceholder = try container.decodeIfPresent(String.self, forKey: .searchBarPlaceholder)
        filtering = try container.decodeIfPresent(Bool.self, forKey: .filtering) ?? true
    }

    init(
        root: String, items: [ExtensionRenderItem] = [], actions: [ExtensionRenderAction] = [],
        fields: [ExtensionRenderField] = [], detail: ExtensionRenderDetail? = nil,
        selectedItemID: String? = nil, loading: Bool = false
    ) {
        self.root = root
        self.items = items
        self.actions = actions
        self.fields = fields
        self.detail = detail
        self.selectedItemID = selectedItemID
        self.loading = loading
        listDropdown = nil
        emptyView = nil
        pagination = nil
        searchBarPlaceholder = nil
        filtering = true
    }
}

struct ExtensionRenderEmptyView: Codable, Equatable, Sendable {
    let title: String
    let description: String?
    let icon: String?
}

struct ExtensionRenderPagination: Codable, Equatable, Sendable {
    let hasMore: Bool
    let cursor: String?
}

struct ExtensionRenderItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String?
    let accessories: [ExtensionRenderAccessory]
    let keywords: [String]
    let actions: [ExtensionRenderAction]
    let detail: ExtensionRenderDetail?

    var primaryAction: ExtensionRenderAction? { actions.first }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        accessories =
            try container.decodeIfPresent([ExtensionRenderAccessory].self, forKey: .accessories) ?? []
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        actions = try container.decodeIfPresent([ExtensionRenderAction].self, forKey: .actions) ?? []
        detail = try container.decodeIfPresent(ExtensionRenderDetail.self, forKey: .detail)
    }
}

struct ExtensionRenderAccessory: Codable, Equatable, Hashable, Identifiable, Sendable {
    let icon: String?
    let text: String?

    var id: String { (icon ?? "") + (text ?? "") }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            icon = nil
            text = value
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }

    private enum CodingKeys: String, CodingKey { case icon, text }
}

struct ExtensionListDropdown: Codable, Equatable, Sendable {
    let id: String
    let tooltip: String
    let value: String
    let options: [ExtensionListDropdownOption]
}

struct ExtensionListDropdownOption: Codable, Equatable, Hashable, Identifiable, Sendable {
    let title: String
    let value: String

    var id: String { value }
}

struct ExtensionRenderAction: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let shortcut: String?
    let section: String?
    let destructive: Bool
    let requiresConfirmation: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        destructive = try container.decodeIfPresent(Bool.self, forKey: .destructive) ?? false
        requiresConfirmation =
            try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
    }
}

struct ExtensionRenderField: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let title: String
    let value: String?
    let error: String?
    let placeholder: String?
    let required: Bool
    let options: [ExtensionPreferenceOption]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        options =
            try container.decodeIfPresent([ExtensionPreferenceOption].self, forKey: .options) ?? []
    }
}

struct ExtensionRenderDetail: Codable, Equatable, Sendable {
    let markdown: String
    let metadata: [ExtensionRenderMetadata]
    let sections: [ExtensionRenderDetailSection]
    let links: [ExtensionRenderDetailLink]

    init(
        markdown: String, metadata: [ExtensionRenderMetadata] = [],
        sections: [ExtensionRenderDetailSection] = [], links: [ExtensionRenderDetailLink] = []
    ) {
        self.markdown = markdown
        self.metadata = metadata
        self.sections = sections
        self.links = links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markdown = try container.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        metadata =
            try container.decodeIfPresent([ExtensionRenderMetadata].self, forKey: .metadata) ?? []
        sections =
            try container.decodeIfPresent([ExtensionRenderDetailSection].self, forKey: .sections) ?? []
        links = try container.decodeIfPresent([ExtensionRenderDetailLink].self, forKey: .links) ?? []
    }
}

struct ExtensionRenderMetadata: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
    let kind: String
}

struct ExtensionRenderDetailSection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let metadata: [ExtensionRenderMetadata]
}

struct ExtensionRenderDetailLink: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: String
}

struct ExtensionCapabilityProgress: Codable, Equatable, Sendable {
    let requestID: String?
    let capability: String?
    let jobID: String?
    let stream: String?
    let chunk: String?
    let done: Bool
    let status: Int?
    let truncated: Bool
    let timedOut: Bool
    let cancelled: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        capability = try container.decodeIfPresent(String.self, forKey: .capability)
        jobID = try container.decodeIfPresent(String.self, forKey: .jobID)
        stream = try container.decodeIfPresent(String.self, forKey: .stream)
        chunk = try container.decodeIfPresent(String.self, forKey: .chunk)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        status = try container.decodeIfPresent(Int.self, forKey: .status)
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        timedOut = try container.decodeIfPresent(Bool.self, forKey: .timedOut) ?? false
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false
    }
}
