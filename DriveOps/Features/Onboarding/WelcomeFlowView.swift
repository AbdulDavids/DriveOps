//
//  WelcomeFlowView.swift
//  DriveOps
//

import SwiftUI

struct WelcomeFlowView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let pages: [WelcomePage] = [
        WelcomePage(
            icon: "car.fill",
            iconColor: .accentColor,
            title: "Welcome to DriveOps",
            body: "A real-time OBD2 diagnostics app built for iOS. Plug in your adapter and know exactly what's going on under the hood."
        ),
        WelcomePage(
            icon: "dot.radiowaves.left.and.right",
            iconColor: .blue,
            title: "Connect Your Adapter",
            body: "Pair your ELM327 adapter over Bluetooth or Wi-Fi. DriveOps will detect your vehicle's protocol automatically."
        ),
        WelcomePage(
            icon: "gauge.with.needle",
            iconColor: .green,
            title: "Live Sensor Data",
            body: "Watch RPM, speed, coolant temp, MAF, throttle position, and more update in real time as you drive."
        ),
        WelcomePage(
            icon: "stethoscope",
            iconColor: .orange,
            title: "Read & Clear DTCs",
            body: "The Diagnostics tab shows every trouble code stored in your ECU, with descriptions and the option to clear them."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, pg in
                    WelcomePageView(page: pg)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut, value: page)

            VStack(spacing: 16) {
                // Dot indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                            .animation(.easeInOut, value: page)
                    }
                }

                if page < pages.count - 1 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("Next")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if page < pages.count - 1 {
                    Button("Skip") {
                        isPresented = false
                    }
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .padding(.top, 12)
        }
    }
}

// MARK: - Page data

private struct WelcomePage {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
}

// MARK: - Single page layout

private struct WelcomePageView: View {
    let page: WelcomePage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(page.iconColor)
                .frame(width: 110, height: 110)
                .background(page.iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeFlowView(isPresented: .constant(true))
}
