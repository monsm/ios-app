// R4 正控：调用点的外部参数标签与声明对不上 ⇒ 四处都该响。
//  (1) 声明 `oid(mac:rowKey:)`，调用按位置传 —— 现网 RecordSearch.oid 的 6 处就是这个形状;
//  (2) 声明 `probe(_ name:)` (首参没有外部标签)，调用却写了 `name:` —— 多写标签;
//  (3) 声明 `legendRow(_ labels:)`，调用写了 `labels:` —— 现网 StatsView 的 legendRow 就是这一处;
//  (4) 第一个标签写对、第二个写错 (`rowKey:` 写成 `key:`) —— 只有**逐位判**才看得见这种。
//      第一百四十八批第二版把判据从"只看首参"扩成"从第 0 位起、连续可判的每一位"，这一条就是它的正控。
// 这份文件不在任何 target 的 sources 里 (project.yml 只收 App/Widget/Tests)，
// 它存在的唯一意义是让"少写标签 / 多写标签 / 写错标签"三种判据各自可被证伪。
import Foundation

enum Hub {
    static func oid(mac: String, rowKey: String) -> String { mac + "#" + rowKey }
    static func probe(_ name: String) -> String { name }
    static func pick(mac: String, rowKey: String) -> String { mac + "|" + rowKey }
    func legendRow(_ labels: [String]) -> String { labels.joined() }

    func build() -> String {
        let a = Hub.oid("AA", "1")
        let b = Hub.probe(name: "x")
        let c = Hub.pick(mac: "AA", key: "1")
        return a + b + c + legendRow(labels: ["y"])
    }
}
