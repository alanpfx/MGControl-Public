import SwiftUI
import CoreKit

struct ChargingRecordsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            if let stats = app.chargingStats {
                Section("累计统计") {
                    HStack {
                        stat("总费用", String(format: "¥%.1f", stats.totalCost))
                        Divider().frame(height: 32)
                        stat("总电量", String(format: "%.1f kWh", stats.totalEnergyKWh))
                        Divider().frame(height: 32)
                        stat("百公里花费", String(format: "¥%.1f", stats.costPer100Km))
                    }
                    HStack {
                        stat("总里程", "\(stats.totalDistanceKm) km")
                        Divider().frame(height: 32)
                        stat("平均电价", String(format: "¥%.2f/kWh", stats.averagePricePerKWh))
                        Spacer().frame(width: 8)
                    }
                }
            }

            Section("充电记录") {
                if app.chargingRecords.isEmpty {
                    Text("暂无充电记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.chargingRecords) { record in
                        row(record)
                    }
                }
            }
        }
        .navigationTitle("充电记录")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if app.chargingRecords.isEmpty { await app.loadChargingData() }
        }
        .refreshable { await app.loadChargingData() }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ record: ChargingRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dateText(record.startTime))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(record.isFastCharge ? "快充" : "慢充")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((record.isFastCharge ? Theme.warning : Theme.accent).opacity(0.15))
                    .clipShape(Capsule())
            }
            HStack(spacing: 6) {
                Text("\(record.startSoc)% → \(record.endSoc)%")
                Text("·")
                Text(String(format: "%.1f kWh", record.energyKWh))
                Spacer()
                Text(String(format: "¥%.2f", record.cost))
                    .font(.subheadline.weight(.medium))
            }
            .font(.footnote)
            Text("\(record.durationMinutes) 分钟" + (record.stationName.map { " · \($0)" } ?? ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
