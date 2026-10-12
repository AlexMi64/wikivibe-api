import Foundation

struct PhoneLinkSnapshot: Encodable {
    struct ServerInfo: Encodable {
        let name: String
        let version: String
        let generatedAt: String
        let demo: Bool
    }
    
    struct Provider: Encodable {
        let id: String
        let displayName: String
        let fidelity: String
        let status: Status
        let windows: [Window]
        let headlineId: String?
        let block: Block?
        let account: Account?
        
        enum CodingKeys: String, CodingKey {
            case id, displayName, fidelity, status, windows, headlineId, block, account
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(fidelity, forKey: .fidelity)
            try container.encode(status, forKey: .status)
            try container.encode(windows, forKey: .windows)
            
            if let headlineId = headlineId { try container.encode(headlineId, forKey: .headlineId) } else { try container.encodeNil(forKey: .headlineId) }
            if let block = block { try container.encode(block, forKey: .block) } else { try container.encodeNil(forKey: .block) }
            if let account = account { try container.encode(account, forKey: .account) } else { try container.encodeNil(forKey: .account) }
        }
    }
    
    struct Status: Encodable {
        let kind: String
        let since: String?
        let why: String?
    }
    
    struct Window: Encodable {
        let id: String
        let label: String
        let usedFraction: Double?
        let remaining: Int?
        let used: Int?
        let resetsAt: String?
        
        enum CodingKeys: String, CodingKey {
            case id, label, usedFraction, remaining, used, resetsAt
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(label, forKey: .label)
            
            if let usedFraction = usedFraction { try container.encode(usedFraction, forKey: .usedFraction) } else { try container.encodeNil(forKey: .usedFraction) }
            if let remaining = remaining { try container.encode(remaining, forKey: .remaining) } else { try container.encodeNil(forKey: .remaining) }
            if let used = used { try container.encode(used, forKey: .used) } else { try container.encodeNil(forKey: .used) }
            if let resetsAt = resetsAt { try container.encode(resetsAt, forKey: .resetsAt) } else { try container.encodeNil(forKey: .resetsAt) }
        }
    }
    
    struct Block: Encodable {
        let reason: String
        let resetsAt: String?
    }
    
    struct Account: Encodable {
        let plan: String
        let source: String
    }
    
    struct Session: Encodable {
        let id: String
        let name: String
        let detail: String
        let state: String
        let waitingFor: String?
        let since: String?
        
        enum CodingKeys: String, CodingKey {
            case id, name, detail, state, waitingFor, since
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(detail, forKey: .detail)
            try container.encode(state, forKey: .state)
            
            if let waitingFor = waitingFor { try container.encode(waitingFor, forKey: .waitingFor) } else { try container.encodeNil(forKey: .waitingFor) }
            if let since = since { try container.encode(since, forKey: .since) } else { try container.encodeNil(forKey: .since) }
        }
    }
    
    let server: ServerInfo
    let providers: [Provider]
    let sessions: [Session]
}
