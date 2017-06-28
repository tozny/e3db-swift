
import Swish
import ResponseDetective
import Result
import Sodium

public struct Client {

    public init() {}

    private static let apiClient: APIClient = {
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)

        print("APIClient")
        let session   = URLSession(configuration: configuration)
        let performer = NetworkRequestPerformer(session: session)
        return APIClient(requestPerformer: performer)
    }()

    public static func register(email: String, findByEmail: Bool = false) {
        guard let keyPair = Sodium()?.box.keyPair() else { return }
        let pubKey = PublicKey(curve25519: keyPair.publicKey.base64URLEncodedString())
        let req = RegisterRequest(email: email, publicKey: pubKey, findByEmail: findByEmail)
        apiClient.perform(req) { result in
            switch result {
            case .success(let resp):
                print("Response: \(resp)")
            case .failure(let err):
                print("Failure: \(err)")
            }
        }
    }
}


