import SwiftUI

struct MyTimeMonthView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var offlineCommissions: CommissionOfflineStore
    @Environment(\.dismiss) private var dismiss

    let onSelectDate: (Date) -> Void

    @State private var displayedMonth = MyTimeMonth(containing: Date())
    @State private var recordedMinutes: [Date: Int] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadRequestID: UUID?

    private let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthNavigation

                if !displayedMonth.calendar.isDate(
                    Date(),
                    equalTo: displayedMonth.startDate,
                    toGranularity: .month
                ) {
                    Button("Aktuellen Monat anzeigen") {
                        showMonth(MyTimeMonth(containing: Date()))
                    }
                }

                if isLoading {
                    ProgressView("Zeiten werden geladen …")
                }

                if let errorMessage {
                    VStack(spacing: 8) {
                        Text("Zeiten konnten nicht geladen werden.")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Erneut versuchen") {
                            Task {
                                await loadMonth()
                            }
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(
                        0..<displayedMonth.leadingEmptyDays,
                        id: \.self
                    ) { _ in
                        Color.clear
                            .frame(height: 70)
                            .accessibilityHidden(true)
                    }

                    ForEach(displayedMonth.dates, id: \.self) { date in
                        dayButton(date)
                    }
                }

                if !isLoading && errorMessage == nil {
                    HStack {
                        Text("Erfasst im Monat")
                        Spacer()
                        Text(
                            WorkTimeText.duration(
                                recordedMinutes.values.reduce(0, +)
                            )
                        )
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Monatsübersicht")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") {
                    dismiss()
                }
            }
        }
        .onChange(of: offlineCommissions.revision) { _, _ in
            if let totals = offlineCommissions.cachedMonthTotals(displayedMonth) { recordedMinutes = totals }
        }
        .task(id: displayedMonth.startDate) {
            await loadMonth()
        }
        .refreshable {
            await loadMonth()
        }
    }

    private var monthNavigation: some View {
        HStack(spacing: 12) {
            Button {
                showMonth(displayedMonth.moving(by: -1))
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Vorheriger Monat")

            Text(displayedMonth.title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Button {
                showMonth(displayedMonth.moving(by: 1))
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Nächster Monat")
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let minutes = recordedMinutes[date]
        let isToday = displayedMonth.calendar.isDateInToday(date)

        return Button {
            onSelectDate(date)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Text(
                    String(displayedMonth.calendar.component(.day, from: date))
                )
                .font(.headline)
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)

                Text(minutes.map { WorkTimeText.duration($0) } ?? "–")
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(
                        (minutes ?? 0) == 0 ? Color.secondary : Color.primary
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                isToday
                    ? Color.accentColor.opacity(0.12)
                    : Color(.secondarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            date.formatted(
                .dateTime.weekday(.wide).day().month(.wide).year()
                    .locale(Locale(identifier: "de_DE"))
            )
        )
        .accessibilityValue(
            minutes.map { WorkTimeText.duration($0) }
                ?? (isLoading ? "Wird geladen" : "Nicht verfügbar")
        )
        .accessibilityHint("Tagesansicht öffnen")
    }

    private func showMonth(_ month: MyTimeMonth) {
        guard month.startDate != displayedMonth.startDate else {
            return
        }

        recordedMinutes = [:]
        errorMessage = nil
        isLoading = true
        displayedMonth = month
    }

    private func loadMonth() async {
        guard !Task.isCancelled else {
            return
        }

        let month = displayedMonth
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        errorMessage = nil
        recordedMinutes = [:]

        defer {
            if loadRequestID == requestID,
               displayedMonth.startDate == month.startDate {
                isLoading = false
            }
        }

        do {
            let totals = try await session.apiClient.fetchMyTimeMonth(month)
            try Task.checkCancellation()

            guard loadRequestID == requestID,
                  displayedMonth.startDate == month.startDate else {
                return
            }

            recordedMinutes = totals
        } catch {
            guard !error.isRequestCancellation,
                  loadRequestID == requestID,
                  displayedMonth.startDate == month.startDate else {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}
