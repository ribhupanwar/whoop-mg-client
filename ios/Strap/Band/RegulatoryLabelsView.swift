import SwiftUI

/// WHOOP 5.80.2 Forensic Regulatory Labels View
/// Extracted directly from WhoopRegulatoryInfo_WhoopRegulatoryInfo.bundle
struct RegulatoryLabelsView: View {
    @EnvironmentObject private var store: AppStore

    private var hardwareHeader: String {
        let model = (store.band.hardwareRevision ?? store.band.modelNumber ?? "").lowercased()
        if model.contains("5") || model.contains("goose") {
            return "5.0 REGULATORY LABELS"
        } else if model.contains("mg") || model.contains("maverick") || model.contains("ws50") {
            return "MG REGULATORY LABELS"
        } else {
            return "4.0 REGULATORY LABELS"
        }
    }

    private var modelIdContent: String {
        let model = (store.band.hardwareRevision ?? store.band.modelNumber ?? "").lowercased()
        if model.contains("5") || model.contains("goose") {
            return "WG50 (DEVICE)\nWD50 (BASIC CHARGER)\nWB50 (WIRELESS CHARGER)"
        } else if model.contains("mg") || model.contains("maverick") || model.contains("ws50") {
            return "WS50 (DEVICE)\nWM50 (DEVICE)\nWD50 (BASIC CHARGER)\nWB50 (WIRELESS CHARGER)"
        } else {
            return "WS40 (DEVICE)\nWP40 (CHARGER)"
        }
    }

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                // Header Banner
                Panel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hardwareHeader)
                            .font(StrapTypography.body(14, weight: .bold))
                            .foregroundStyle(Color.appFG)

                        Text("Official regulatory markings and wireless certifications for your WHOOP hardware.")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                    }
                }

                // Model ID
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MODEL ID")
                            .font(StrapTypography.metric(10, weight: .bold))
                            .foregroundStyle(Color.appMuted)

                        Text(modelIdContent)
                            .font(StrapTypography.body(12, weight: .medium))
                            .foregroundStyle(Color.appFG)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // International Certifications
                Panel {
                    SectionTitle("INTERNATIONAL COMPLIANCE")

                    regulatoryRow(region: "UNITED STATES", cert: "FCC ID: 2ADXO-WS40 / 2ADXO-WS50\nComplies with Part 15 of FCC Rules.")
                    Divider().background(Color.appLine)
                    regulatoryRow(region: "CANADA", cert: "IC: 21107-WS40 / 21107-WS50\nCAN ICES-003(B) / NMB-003(B)")
                    Divider().background(Color.appLine)
                    regulatoryRow(region: "EUROPE", cert: "CE Conformity\nRadio Equipment Directive 2014/53/EU\nRoHS 2011/65/EU")
                    Divider().background(Color.appLine)
                    regulatoryRow(region: "AUSTRALIA\nNEW ZEALAND", cert: "RCM Compliance Standard AS/NZS 4268")
                    Divider().background(Color.appLine)
                    regulatoryRow(region: "SINGAPORE", cert: "Complies with IMDA Standards")
                    Divider().background(Color.appLine)
                    regulatoryRow(region: "SOUTH AFRICA", cert: "TA-2021 / 2643\nTA-2024 / 0465\nAPPROVED")
                }
            }
            .padding(.top, 4)
        }
        .navigationTitle("Regulatory Labels")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func regulatoryRow(region: String, cert: String) -> some View {
        HStack(alignment: .top) {
            Text(region)
                .font(StrapTypography.body(11, weight: .bold))
                .foregroundStyle(Color.appMuted)
                .frame(width: 100, alignment: .leading)

            Spacer()

            Text(cert)
                .font(StrapTypography.body(11))
                .foregroundStyle(Color.appFG)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}
