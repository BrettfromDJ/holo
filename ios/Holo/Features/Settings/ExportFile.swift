import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Your data as one JSON file, like the website's Settings → Export: every transaction (edits
/// and deletions included, as recorded), the watchlist and the products they refer to. Built
/// when you share it, not before.
struct ExportFile: Transferable {
    var transactions: [Txn]
    var watchlist: [WatchRow]
    var products: [String: Product]
    var mode: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("holo-\(file.mode)-\(Format.day()).json")
            try file.data().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    func data() throws -> Data {
        let txns: [[String: Any]] = transactions.map { t in
            var row: [String: Any] = [
                "id": t.id, "productId": t.identity.productId, "printing": t.identity.printing as Any,
                "condition": t.identity.condition, "type": t.kind.rawValue, "date": t.date,
                "quantity": t.quantity, "unitPrice": t.unitPrice, "fees": t.fees, "shipping": t.shipping, "tax": t.tax,
                "createdAt": t.createdAt, "source": t.source as Any, "notes": t.notes as Any, "correctsId": t.correctsId as Any,
            ]
            if let company = t.identity.gradeCompany, let grade = t.identity.grade { row["grade"] = ["company": company, "grade": grade] }
            return row
        }
        let watch: [[String: Any]] = watchlist.map {
            ["id": $0.id, "productId": $0.product_id, "printing": $0.printing as Any, "targetPrice": $0.target_price as Any, "notes": $0.notes as Any, "createdAt": $0.created_at]
        }
        let encoder = JSONEncoder()
        let productsJSON = try JSONSerialization.jsonObject(with: encoder.encode(products))
        let body: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "mode": mode,
            "transactions": txns,
            "watchlist": watch,
            "products": productsJSON,
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
    }
}
