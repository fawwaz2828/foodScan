//
//  A2AProtocol.swift
//  foodScan
//
//  ============================================================================
//  A2A — AGENT-TO-AGENT PROTOCOL (implementasi gaya Google Agent2Agent)
//  ============================================================================
//  File ini mendefinisikan TIPE DATA protokol A2A yang dipakai antar-agent:
//
//   • AgentCard       — "kartu nama" agent (capability discovery): nama, URL,
//                        versi, kemampuan, dan daftar skill yang ditawarkan.
//   • Message / Part  — pesan berperan (user/agent) berisi bagian text/data/file.
//   • Task / Status   — unit kerja yang dikirim antar-agent + status & artifact.
//   • A2ARequest/Response — amplop JSON-RPC 2.0 (method "message/send").
//
//  Berbeda dari `AgentEventDelegate` (kolaborasi internal in-process), A2A adalah
//  PROTOKOL FORMAL berbasis pesan: setiap permintaan benar-benar di-serialize ke
//  JSON lalu di-parse ulang di sisi penerima (lihat A2ANetwork) — sehingga agent
//  bisa dipindah ke proses/host lain (mis. HTTP) tanpa mengubah kontrak.
//  ============================================================================
//

import Foundation

// MARK: - Agent Card (capability discovery)

/// Metadata publik sebuah agent A2A. Klien memakai ini untuk menemukan agent
/// dan tahu skill apa yang bisa diminta — setara "Agent Card" pada spec A2A.
struct AgentCard: Codable, Equatable {
    let name: String
    let description: String
    /// Alamat logis agent (di sini skema lokal `a2a://`; bisa diganti https://).
    let url: String
    let version: String
    let capabilities: AgentCapabilities
    let skills: [AgentSkill]
}

struct AgentCapabilities: Codable, Equatable {
    let streaming: Bool
}

/// Satu skill/kemampuan yang ditawarkan agent (dipakai untuk pencocokan tugas).
struct AgentSkill: Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let tags: [String]
}

// MARK: - Message & Part

/// Peran pengirim pesan dalam percakapan A2A.
enum A2ARole: String, Codable, Equatable {
    case user
    case agent
}

/// Satu bagian pesan. A2A membedakan tipe lewat diskriminator `kind`.
enum A2APart: Codable, Equatable {
    case text(String)
    case data(json: String)                               // payload JSON terstruktur
    case file(name: String, mimeType: String, bytesBase64: String)

    private enum CodingKeys: String, CodingKey {
        case kind, text, data, name, mimeType, bytes
    }
    private enum Kind: String, Codable { case text, data, file }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode(Kind.text, forKey: .kind)
            try c.encode(t, forKey: .text)
        case .data(let json):
            try c.encode(Kind.data, forKey: .kind)
            try c.encode(json, forKey: .data)
        case .file(let name, let mime, let bytes):
            try c.encode(Kind.file, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(mime, forKey: .mimeType)
            try c.encode(bytes, forKey: .bytes)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try c.decode(String.self, forKey: .text))
        case .data:
            self = .data(json: try c.decode(String.self, forKey: .data))
        case .file:
            self = .file(name: try c.decode(String.self, forKey: .name),
                         mimeType: try c.decode(String.self, forKey: .mimeType),
                         bytesBase64: try c.decode(String.self, forKey: .bytes))
        }
    }
}

/// Satu pesan dalam tugas A2A.
struct A2AMessage: Codable, Equatable {
    let role: A2ARole
    let parts: [A2APart]
    let messageId: String

    init(role: A2ARole, parts: [A2APart], messageId: String = UUID().uuidString) {
        self.role = role
        self.parts = parts
        self.messageId = messageId
    }
}

extension Array where Element == A2APart {
    /// Bagian file pertama (mis. foto makanan) bila ada.
    var firstFile: (name: String, mimeType: String, bytesBase64: String)? {
        for p in self { if case let .file(n, m, b) = p { return (n, m, b) } }
        return nil
    }
    /// Payload JSON dari bagian data pertama bila ada.
    var firstDataJSON: String? {
        for p in self { if case let .data(json) = p { return json } }
        return nil
    }
    /// Teks gabungan dari semua bagian text.
    var combinedText: String {
        compactMap { if case let .text(t) = $0 { return t } else { return nil } }
            .joined(separator: " ")
    }
}

// MARK: - Task & Artifact

/// Status siklus hidup tugas A2A.
enum A2ATaskState: String, Codable, Equatable {
    case submitted
    case working
    case completed
    case failed
}

struct A2ATaskStatus: Codable, Equatable {
    let state: A2ATaskState
    let message: A2AMessage?

    init(state: A2ATaskState, message: A2AMessage? = nil) {
        self.state = state
        self.message = message
    }
}

/// Hasil/keluaran yang diproduksi agent untuk sebuah tugas.
struct A2AArtifact: Codable, Equatable {
    let artifactId: String
    let name: String?
    let parts: [A2APart]

    init(artifactId: String = UUID().uuidString, name: String? = nil, parts: [A2APart]) {
        self.artifactId = artifactId
        self.name = name
        self.parts = parts
    }
}

/// Unit kerja yang dipertukarkan antar-agent.
struct A2ATask: Codable, Equatable {
    let id: String
    let contextId: String
    let status: A2ATaskStatus
    let artifacts: [A2AArtifact]

    init(id: String = UUID().uuidString,
         contextId: String = UUID().uuidString,
         status: A2ATaskStatus,
         artifacts: [A2AArtifact] = []) {
        self.id = id
        self.contextId = contextId
        self.status = status
        self.artifacts = artifacts
    }

    /// Payload JSON dari artifact data pertama (jalur cepat untuk klien).
    var firstArtifactDataJSON: String? {
        artifacts.first?.parts.firstDataJSON
    }
}

// MARK: - JSON-RPC 2.0 envelopes

/// Parameter untuk method `message/send`.
struct A2AMessageSendParams: Codable, Equatable {
    let message: A2AMessage
}

/// Permintaan JSON-RPC 2.0 (hanya `message/send` yang didukung saat ini).
struct A2ARequest: Codable, Equatable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: A2AMessageSendParams

    init(id: String = UUID().uuidString,
         method: String = "message/send",
         params: A2AMessageSendParams) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Objek error JSON-RPC; juga bisa dilempar sebagai Swift `Error`.
struct A2AErrorObject: Codable, Equatable, Error, LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

/// Balasan JSON-RPC 2.0.
struct A2AResponse: Codable, Equatable {
    let jsonrpc: String
    let id: String
    let result: A2ATask?
    let error: A2AErrorObject?

    init(id: String, result: A2ATask? = nil, error: A2AErrorObject? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    static func failure(id: String, code: Int, message: String) -> A2AResponse {
        A2AResponse(id: id, error: A2AErrorObject(code: code, message: message))
    }
}

// MARK: - Server contract

/// Kontrak agent yang "menyajikan" dirinya lewat A2A: mengiklankan AgentCard
/// dan menangani permintaan JSON-RPC. Setara sisi-server pada spec A2A.
protocol A2AServer: AnyObject {
    var card: AgentCard { get }
    func handle(_ request: A2ARequest) async -> A2AResponse
}
