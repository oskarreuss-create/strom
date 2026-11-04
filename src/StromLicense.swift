import Foundation
import AppKit
import CryptoKit
import Security
import LocalAuthentication

private enum LicenseFailure: Error { case storage, invalidToken, unconfigured, network, remote(String) }
private struct LicenseSaved: Codable, Sendable { let key: String; let token: String }
private struct LicensePayload: Codable { let version: Int; let platform: String; let device: String; let license_id: String; let issued_at: Int64 }
private struct LicenseReply: Codable { let license: String?; let deactivated: Bool?; let error: String? }
private struct LicenseStorage: Sendable {
    let service: String
    private func query(_ account: String) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecUseAuthenticationContext as String:context]
    }
    func read(_ account: String) throws -> Data? {
        var q=query(account);q[kSecReturnData as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne
        var result: CFTypeRef?;let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status==errSecItemNotFound { return nil }
        guard status==errSecSuccess,let data=result as? Data else { throw LicenseFailure.storage };return data
    }
    func write(_ data: Data, account: String) throws {
        let q=query(account), attributes:[String:Any]=[kSecValueData as String:data]
        let status=SecItemUpdate(q as CFDictionary,attributes as CFDictionary)
        if status==errSecItemNotFound {
            var add=q;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else { throw LicenseFailure.storage }
        } else if status != errSecSuccess { throw LicenseFailure.storage }
    }
    func delete(_ account: String) throws {
        let status=SecItemDelete(query(account) as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else { throw LicenseFailure.storage }
    }
    func identity(create: Bool) throws -> Curve25519.Signing.PrivateKey {
        if let data=try read("device-key") { return try Curve25519.Signing.PrivateKey(rawRepresentation:data) }
        guard create else { throw LicenseFailure.storage }
        let key=Curve25519.Signing.PrivateKey();try write(key.rawRepresentation,account:"device-key");return key
    }
    func saved() throws -> LicenseSaved? {
        guard let data=try read("activation") else { return nil }
        guard let saved=try? JSONDecoder().decode(LicenseSaved.self,from:data) else { throw LicenseFailure.storage };return saved
    }
}
@MainActor final class StromLicense: ObservableObject {
    @Published private(set) var active = false
    @Published var busy = false
    @Published var error = ""
    private let storage = LicenseStorage(service:(Bundle.main.bundleIdentifier ?? "ch.strom.localtest") + ".license.v1")
    private let platform = "macos"
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var serviceURL: URL? { verifiedURL(info["StromLicenseServiceURL"] as? String) }
    var checkoutURL: URL? { verifiedURL(info["StromCheckoutMacURL"] as? String) }
    func recoveryURL(language: String) -> URL? {
        guard let base=serviceURL, var components=URLComponents(url:base.appendingPathComponent("recover"), resolvingAgainstBaseURL:false) else{return nil}
        components.queryItems=[URLQueryItem(name:"lang",value:["ru","en","de","fr","it","es"].contains(language) ? language : "en")]
        return components.url
    }
    private var publicKey: Curve25519.Signing.PublicKey? {
        guard let text=info["StromLicensePublicKey"] as? String,let raw=Data(base64Encoded:text) else{return nil}
        return try? Curve25519.Signing.PublicKey(rawRepresentation:raw)
    }
    var configured: Bool { serviceURL != nil && checkoutURL != nil && publicKey != nil }
    var supportEmail: String? {
        guard let email=info["StromSupportEmail"] as? String,email.contains("@"),!email.lowercased().hasSuffix("@example.com") else{return nil};return email
    }
    var featureAccess: Bool { !configured || active }
    init() { Task { await refresh() } }
    private func verifiedURL(_ text: String?) -> URL? {
        guard let text,let url=URL(string:text),let host=url.host,!host.isEmpty,url.user==nil,url.password==nil else{return nil}
        #if STROM_LICENSE_TESTING
        if url.scheme=="http" && ["127.0.0.1","localhost"].contains(host){return url}
        #endif
        return url.scheme=="https" && !host.hasSuffix("example.com") ? url : nil
    }
    private func encode64(_ data:Data)->String {data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")}
    private func decode64(_ text:String)->Data? {var x=text.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/");x += String(repeating:"=",count:(4-x.count%4)%4);return Data(base64Encoded:x)}
    private func valid(_ token:String,device:String)->Bool {
        let parts=token.split(separator:".",omittingEmptySubsequences:false);guard parts.count==2,let key=publicKey,let signature=decode64(String(parts[1])),let body=decode64(String(parts[0])),let payload=try? JSONDecoder().decode(LicensePayload.self,from:body),payload.version==1,payload.platform==platform,payload.device==device else{return false}
        return key.isValidSignature(signature,for:Data(parts[0].utf8))
    }
    func refresh() async {
        guard configured else {active=false;return}
        let store=storage
        do {
            let result=try await Task.detached { () throws -> (LicenseSaved, Data)? in
                guard let activation=try store.saved() else{return nil};let id=try store.identity(create:false);return (activation,id.publicKey.rawRepresentation)
            }.value
            guard let (activation,device)=result else {active=false;return}
            guard valid(activation.token,device:encode64(device)) else {active=false;return}
            active=true
            do {
                let reply=try await perform("activate",key:activation.key)
                guard let token=reply.license,valid(token,device:encode64(device)) else {active=false;return}
                let refreshed=try JSONEncoder().encode(LicenseSaved(key:activation.key,token:token))
                try await Task.detached { try store.write(refreshed,account:"activation") }.value
            } catch LicenseFailure.remote(let code) where code=="invalid_license" || code=="invalid_key" {
                try? await Task.detached { try store.delete("activation") }.value
                active=false
            } catch {
                // Keep the signed cached license usable while the service is offline.
            }
        } catch {active=false;self.error=errorMessage(error)}
    }
    private func perform(_ action:String,key:String) async throws -> LicenseReply {
        guard let base=serviceURL,publicKey != nil else{throw LicenseFailure.unconfigured}
        let store=storage
        let id=try await Task.detached {try store.identity(create:true)}.value
        let device=encode64(id.publicKey.rawRepresentation),nonce=UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),timestamp=Int64(Date().timeIntervalSince1970*1000)
        let keyHash=SHA256.hash(data:Data(key.utf8)).map{String(format:"%02x",$0)}.joined(),message="\(action)\n\(keyHash)\n\(platform)\n\(device)\n\(nonce)\n\(timestamp)"
        let signature=encode64(try id.signature(for:Data(message.utf8)))
        let object:[String:Any]=["key":key,"platform":platform,"device":device,"nonce":nonce,"timestamp":timestamp,"signature":signature]
        var request=URLRequest(url:base.appendingPathComponent("v1").appendingPathComponent(action));request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.httpBody=try JSONSerialization.data(withJSONObject:object);request.timeoutInterval=25
        let(data,response)=try await URLSession.shared.data(for:request);guard let http=response as? HTTPURLResponse else{throw LicenseFailure.network}
        let reply=try JSONDecoder().decode(LicenseReply.self,from:data);guard (200..<300).contains(http.statusCode) else{throw LicenseFailure.remote(reply.error ?? "unknown")};return reply
    }
    func activate(_ input:String) async {
        guard !busy else{return};error="";busy=true;defer{busy=false}
        do {
            let key=input.trimmingCharacters(in:.whitespacesAndNewlines);guard !key.isEmpty else{throw LicenseFailure.remote("invalid_key")}
            let reply=try await perform("activate",key:key),store=storage
            let device=try await Task.detached {try store.identity(create:false).publicKey.rawRepresentation}.value
            guard let token=reply.license,valid(token,device:encode64(device)) else{throw LicenseFailure.invalidToken}
            let encoded=try JSONEncoder().encode(LicenseSaved(key:key,token:token));try await Task.detached {try store.write(encoded,account:"activation")}.value
            await refresh()
        }catch{self.error=errorMessage(error)}
    }
    func deactivate() async {
        guard !busy else{return};error="";busy=true;defer{busy=false};let store=storage
        do {
            guard let data=try await Task.detached(operation:{try store.saved()}).value else{throw LicenseFailure.storage}
            let response=try await perform("deactivate",key:data.key);guard response.deactivated==true else{throw LicenseFailure.network}
            try await Task.detached {try store.delete("activation")}.value;active=false
        }catch{self.error=errorMessage(error)}
    }
    private func errorMessage(_ error:Error)->String {
        if let problem=error as? LicenseFailure {
            switch problem {case .remote(let code):if code=="already_active" || code=="activation_failed"{return "Лицензия уже активирована на другом устройстве."};if code=="invalid_license" || code=="invalid_key"{return "Ключ не подходит для этой версии STRÖM."};return "Не удалось связаться с сервисом лицензий."
            case .storage:return "Не удалось сохранить лицензию в Связке ключей."
            case .invalidToken:return "Не удалось проверить подлинность лицензии."
            case .unconfigured:return "Продажи и активация пока не настроены."
            case .network:return "Не удалось связаться с сервисом лицензий."}
        }
        return "Не удалось связаться с сервисом лицензий."
    }
}
