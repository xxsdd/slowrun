import Foundation
import RunCore

enum ServiceError: LocalizedError {
    case notConfigured, invalidResponse, requestFailed(Int), connectionFailed, timedOut
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先在设置中配置可达的服务地址和访问令牌。"
        case .invalidResponse: return "服务响应格式不正确。"
        case .connectionFailed: return "无法连接 AI 服务。若地址是 192.168、10 或 172 开头的家庭地址，移动网络无法访问；请在设置中使用云端 HTTPS 地址。"
        case .timedOut: return "AI 服务等待超时，未自动重试；请稍后手动重试。"
        case .requestFailed(let status):
            switch status {
            case 401: return "访问令牌不正确，请检查设置。"
            case 429: return "服务配额或请求频率受限，未自动重试。"
            case 503: return "服务尚未配置对应的语音或 AI 提供者。"
            case 502: return "AI 提供者请求失败，请检查模型权限和账户额度；未自动重试。"
            case 504: return "AI 提供者响应超时，未自动重试。"
            default: return "服务请求失败（\(status)），未自动重试。"
            }
        }
    }
}
struct ServiceClient {
    let baseURL: URL
    let token: String
    private func post(path: String, body: [String: Any], timeout: Double) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("SlowRunPersonal/2", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError { throw error.code == .timedOut ? ServiceError.timedOut : ServiceError.connectionFailed }
        guard let response = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw ServiceError.requestFailed(response.statusCode) }
        return (data, response)
    }
    func checkConnection() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"), timeoutInterval: 8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("SlowRunPersonal/2", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ServiceError.connectionFailed }
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ServiceError.requestFailed(http.statusCode) }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any], body["ai_configured"] as? Bool == true else { throw ServiceError.requestFailed(503) }
    }
    func review(_ record: WorkoutRecord) async throws -> String {
        let metrics: [String: Any] = ["plan": record.plan.rawValue, "distance_m": record.mainMeters, "duration_s": record.mainSeconds, "splits_s": record.splits.map(\.seconds), "effort": record.effort?.rawValue ?? "unspecified", "completed": record.isCompleted]
        let (data, _) = try await post(path: "v1/analysis", body: metrics, timeout: 35)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = object["analysis"] as? String, !text.isEmpty else { throw ServiceError.invalidResponse }
        return String(text.prefix(1_500))
    }
}
