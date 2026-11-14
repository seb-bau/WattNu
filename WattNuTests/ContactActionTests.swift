import Foundation
import Testing
@testable import WattNu

@MainActor
struct ContactActionTests {
    @Test func phoneNumbersUseOnlyTheTelephoneScheme() throws {
        let url = try #require(ContactActionDestination.url(scheme: "tel", value: "+49 (0)2306 / 12-34"))
        #expect(url.scheme == "tel")
        #expect(url.absoluteString == "tel:+4923061234")
    }

    @Test func emailAddressesUseOnlyTheMailScheme() throws {
        let url = try #require(ContactActionDestination.url(scheme: "mailto", value: " person+work@example.invalid "))
        #expect(url.scheme == "mailto")
        #expect(url.path == "person+work@example.invalid")
        #expect(url.query == nil)
    }

    @Test func invalidActionsAreNotOpened() {
        #expect(ContactActionDestination.url(scheme: "tel", value: "Keine Nummer") == nil)
        #expect(ContactActionDestination.url(scheme: "mailto", value: "keine Adresse") == nil)
        #expect(ContactActionDestination.url(scheme: "https", value: "example.invalid") == nil)
    }
}
