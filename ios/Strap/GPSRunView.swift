import SwiftUI

struct GPSRunView: View {
    @StateObject private var gps = GPSRunRecorder()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 12) {
                Panel {
                    SectionTitle("Outdoor GPS run")
                    Text(String(format: "%.2f km", gps.distanceMeters / 1000))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    Text("Elapsed: \\(gps.elapsedSeconds / 60)m \\(gps.elapsedSeconds % 60)s")
                        .foregroundStyle(Color.appMuted)
                    Text(gps.status)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                    HStack(spacing: 14) {
                        if !gps.recording {
                            Button("Start GPS") { gps.start() }
                        } else {
                            Button(gps.paused ? "Resume" : "Pause") {
                                if gps.paused { gps.resume() } else { gps.pause() }
                            }
                            Button("Finish") { gps.stop() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    Hint("Uses iPhone GPS while this screen is active. Accurate fixes only; location permissions required. Background GPS and saved route history are not yet supported.")
                }
                Panel {
                    SectionTitle("Kilometre splits")
                    if gps.splitSeconds.isEmpty {
                        Hint("Splits appear after each completed kilometre.")
                    } else {
                        ForEach(Array(gps.splitSeconds.enumerated()), id: \.offset) { index, seconds in
                            HStack {
                                Text("KM \\(index + 1)")
                                Spacer()
                                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appFG)
                        }
                    }
                }
            }
        }
        .navigationTitle("GPS Run")
        .onReceive(ticker) { _ in gps.refreshElapsed() }
        .onDisappear { if gps.recording { gps.stop() } }
    }
}
