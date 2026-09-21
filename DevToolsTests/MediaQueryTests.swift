import Foundation
import Testing
@testable import DevTools

struct MediaQueryTests {
    private func query(_ params: [QueryParam]) -> String {
        params.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    private func term(_ key: String, _ type: MediaFieldType, _ op: String, _ value: String) -> MediaQuery.Term {
        var t = MediaQuery.Term(field: MediaField(key: key, title: key, type: type))
        t.operatorKey = op
        t.value = value
        return t
    }

    @Test func operatorCharactersRideOnTheKey() {
        var q = MediaQuery()
        q.sectionKey = "1"
        q.type = 1
        q.terms = [
            term("year", .integer, ">>=", "2000"),
            term("addedAt", .date, ">>=", "-3y"),
            term("title", .string, "==", "Heat"),
            term("title", .string, "!==", "Heat 2"),
            term("rating", .integer, ">=", "8"),
        ]
        #expect(query(q.queryParams) == "type=1&year>>=2000&addedAt>>=-3y&title==Heat&title!==Heat 2&rating>=8")
        #expect(q.path == "/library/sections/1/all")
    }

    @Test func booleansEmitOneOrZeroAndNeverNeedAValue() {
        var q = MediaQuery()
        q.sectionKey = "1"
        q.type = 1
        let unwatched = term("unwatched", .boolean, "=", "1")
        var watched = term("unwatched", .boolean, "=", "0")
        watched.value = "0"
        q.terms = [unwatched, watched]
        #expect(query(q.queryParams) == "type=1&unwatched=1&unwatched=0")
        #expect(MediaQuery.Term(field: MediaField(key: "unwatched", title: "", type: .boolean)).isActive)
    }

    @Test func emptyValuesAreSkippedAndMatchAnyInsertsOr() {
        var q = MediaQuery()
        q.sectionKey = "2"
        q.type = 4
        q.matchAny = true
        q.terms = [
            term("index", .integer, "=", "1"),
            term("title", .string, "=", ""),
            term("rating", .integer, "=", "2"),
        ]
        #expect(query(q.queryParams) == "type=4&index=1&or=1&rating=2")
    }

    @Test func sortGroupAndLimitAreEmittedInOrder() {
        var q = MediaQuery()
        q.sectionKey = "3"
        q.type = 10
        q.sorts = [MediaQuery.Sort(key: "ratingCount", descending: true), MediaQuery.Sort(key: "title")]
        q.group = "title"
        q.limit = " 100 "
        #expect(query(q.queryParams) == "type=10&sort=ratingCount:desc,title&group=title&limit=100")
    }

    @Test func requestURLEncodesOperatorCharactersOnTheKey() throws {
        var q = MediaQuery()
        q.sectionKey = "1"
        q.type = 1
        q.terms = [term("year", .integer, ">>=", "2000")]
        let url = try #require(q.request().url(base: URL(string: "http://host:32400")!))
        #expect(url.absoluteString.contains("year%3E%3E=2000"))
        #expect(!url.absoluteString.contains("X-Plex-Token"))
    }

    @Test func documentedOperatorsPerType() {
        #expect(MediaFieldType.string.operators.map(\.key) == ["=", "!=", "==", "!==", "<=", ">="])
        #expect(MediaFieldType.date.operators.map(\.key) == ["=", "!=", ">>=", "<<="])
        #expect(MediaFieldType.integer.operators.map(\.key) == ["=", "!=", ">>=", "<<=", ">=", "<="])
        #expect(MediaFieldType.boolean.operators.map(\.key) == ["="])
        #expect(MediaFieldType(raw: "resolution") == .other("resolution"))
    }

    @Test func sectionDetailsParseTypesFieldsAndSorts() throws {
        let json = """
        {"MediaContainer":{"Type":[
          {"key":"/library/sections/1/all?type=1","type":"movie","title":"Movies",
           "Field":[{"key":"title","title":"Title","type":"string"},
                    {"key":"addedAt","title":"Date Added","type":"date"},
                    {"key":"unwatched","title":"Unwatched","type":"boolean"}],
           "Sort":[{"key":"titleSort","title":"Title","descKey":"titleSort:desc"},
                   {"key":"rating","title":"Rating"}]},
          {"type":"collection","title":"Collections"}
        ]}}
        """
        let root = try #require(JSONNodeParser.parse(Data(json.utf8)))
        let details = SectionDetails(root: root)
        #expect(details.types.map(\.number) == [1, 18])
        let movie = details.types[0]
        #expect(movie.fields.map(\.key) == ["title", "addedAt", "unwatched"])
        #expect(movie.fields[1].type == .date)
        #expect(movie.fields[2].type == .boolean)
        #expect(movie.sorts.map(\.key) == ["titleSort", "rating"])
        #expect(details.types[1].fields.isEmpty)
    }

    @Test func sectionDetailsParseFiltersAndMatchThemToFields() throws {
        let json = """
        {"MediaContainer":{"Type":[
          {"key":"/library/sections/1/all?type=1","type":"movie","title":"Movies",
           "Field":[{"key":"title","title":"Title","type":"string"},
                    {"key":"studio","title":"Studio","type":"string"},
                    {"key":"genre","title":"Genre","type":"tag"}],
           "Filter":[{"filter":"genre","filterType":"string","key":"/library/sections/1/genre?type=1","title":"Genre","type":"filter"},
                     {"filter":"studio","filterType":"string","key":"/library/sections/1/studio?type=1","title":"Studio","type":"filter"},
                     {"filter":"nokey","title":"Broken"}]}
        ]}}
        """
        let root = try #require(JSONNodeParser.parse(Data(json.utf8)))
        let movie = try #require(SectionDetails(root: root).types.first)
        #expect(movie.filters.map(\.filter) == ["genre", "studio"])
        #expect(movie.filter(for: "studio")?.valuesKey == "/library/sections/1/studio?type=1")
        #expect(movie.filter(for: "title") == nil)
    }

    @Test func filterValuesComeFromDirectoryKeysAndTitles() throws {
        let genres = try #require(JSONNodeParser.parse(Data("""
        {"MediaContainer":{"Directory":[
          {"fastKey":"/library/sections/1/all?genre=12","key":"12","title":"Action"},
          {"key":"7","title":"Drama"},
          {"title":"no key"}
        ]}}
        """.utf8)))
        let values = MediaFilterValue.parse(root: genres)
        #expect(values.map(\.key) == ["12", "7"])
        #expect(values.map(\.title) == ["Action", "Drama"])
        #expect(!MediaFilterValue.keysAreValues(values))

        let studios = try #require(JSONNodeParser.parse(Data("""
        {"MediaContainer":{"Directory":[{"key":"Warner Bros.","title":"Warner Bros."},{"key":"A24","title":"A24"}]}}
        """.utf8)))
        #expect(MediaFilterValue.keysAreValues(MediaFilterValue.parse(root: studios)))
        #expect(!MediaFilterValue.keysAreValues([]))
    }

    @Test func termLabelIsNeverEmitted() {
        var q = MediaQuery()
        q.sectionKey = "1"
        q.type = 1
        var genre = term("genre", .tag, "=", "12")
        genre.label = "Action"
        q.terms = [genre]
        #expect(query(q.queryParams) == "type=1&genre=12")
    }
}
