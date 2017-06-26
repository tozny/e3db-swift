
import Swish
import ResponseDetective
import Result

enum StringParserError: Error {
    case badData(Any)
    case invalidUTF8(Data)
    case unexpectedResponse(String)
}

struct StringParser: Parser {
    typealias Representation = String

    static func parse(_ object: Any) -> Result<String, SwishError> {
        guard let data = object as? Data else {
            return .failure(.parseError(StringParserError.badData(object)))
        }

        guard let string = String(data: data, encoding: .utf8) else {
            return .failure(.parseError(StringParserError.invalidUTF8(data)))
        }

        return .success(string)
    }
}


struct HealthRequest: Request {
    typealias ResponseObject = String
    typealias ResponseParser = StringParser

    func build() -> URLRequest {
        let endpoint = URL(string: "https://api.e3db.com/v1/storage/healthcheck")!
        return URLRequest(url: endpoint)
    }

    func parse(_ string: String) -> Result<String, SwishError> {
        print("parsing string: \(string)")
        switch string {
        case "Ok":
            return .success("Good")
        default:
            return .failure(.parseError(StringParserError.unexpectedResponse(string)))
        }
    }
}

enum E3dbError: Error {
    case deserialize
}

struct DataDeserializer: Deserializer {
    func deserialize(_ data: Data?) -> Result<Any, SwishError> {
        guard let data = data, !data.isEmpty else {
            return .success(NSNull())
        }

        return .success(data)
    }
}

public struct Client {
    let baseApiUrl = "https://api.e3db.com/v1/storage"

    public static func healthCheck() {
        let configuration = URLSessionConfiguration.default
        ResponseDetective.enable(inConfiguration: configuration)

        let session   = URLSession(configuration: configuration)
        let performer = NetworkRequestPerformer(session: session)
        let client    = APIClient(requestPerformer: performer, deserializer: DataDeserializer())

        let request = HealthRequest()

        client.perform(request) { result in
            switch result {
            case .success(let resp):
                print("\(resp) request!")

            case let .failure(error):
                print("Failed! \(error)")
            }
        }

    }

}


