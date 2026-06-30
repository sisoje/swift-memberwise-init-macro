import Foundation
import PublicMirror

// A shared-models package: plain data the app and other packages couple to.
// You author the underscored, internal source-of-truth structs; @PublicMirror
// emits the public twins beside them. Inside an `enum` namespace, the twins land
// in the same namespace, so consumers reference e.g. `Models.User`.

public enum Models {

    @PublicMirror
    struct _User {
        let id: UUID
        let name: String
        var isActive: Bool = false
    }

    @PublicMirror
    struct _Address: Equatable, Codable, Sendable {
        let street: String
        let city: String
        let postalCode: String
    }

    public enum Request {
        @PublicMirror
        struct _UpdateName {
            let userID: UUID
            let newName: String
        }
    }
}

// Consumers write:
//
//   let user = Models.User(id: UUID(), name: "Ada")
//   let req  = Models.Request.UpdateName(userID: user.id, newName: "Ada L.")
//
// The underscored `_User` / `_Address` / `_UpdateName` originals are write-only
// macro input — nothing outside this file should reference them.
