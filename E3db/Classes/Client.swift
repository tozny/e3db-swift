
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

    public static func register(email: String, findByEmail: Bool, completion: @escaping (Result<Config, E3dbError>) -> Void) {
        guard let keyPair = Sodium()?.box.keyPair()
            else { return }

        let pubKey = PublicKey(curve25519: keyPair.publicKey.base64URLEncodedString())
        let req = RegisterRequest(email: email, publicKey: pubKey, findByEmail: findByEmail)
        apiClient.perform(req) { result in
            completion(
                result.mapError { E3dbError.configError($0.localizedDescription) }
                    .map { resp in
                        Config(
                            version: 1,
                            baseApiUrl: Endpoints.apiUrl.absoluteString,
                            apiKeyId: resp.apiKeyId,
                            apiSecret: resp.apiSecret,
                            clientId: resp.clientId,
                            clientEmail: email,
                            publicKey: pubKey.curve25519,
                            privateKey: keyPair.secretKey.base64URLEncodedString()
                        )
                }
            )
        }
    }
}


