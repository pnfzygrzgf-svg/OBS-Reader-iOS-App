// SPDX-License-Identifier: GPL-3.0-or-later

// OnboardingView.swift

import SwiftUI

/// Einfaches 3-Seiten Onboarding beim ersten Start.
///
/// Seiten:
/// 1. Willkommen - App-Zweck erklären
/// 2. Sensor verbinden - Bluetooth-Hinweis
/// 3. Aufnahme starten - Kurze Anleitung
struct OnboardingView: View {

    /// Callback wenn Onboarding abgeschlossen
    let onComplete: () -> Void

    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    sensorPage.tag(1)
                    recordPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page Indicator + Button
                VStack(spacing: OBSSpacing.xl) {
                    pageIndicator

                    Button {
                        if currentPage < 2 {
                            withAnimation { currentPage += 1 }
                        } else {
                            onComplete()
                        }
                    } label: {
                        Text(currentPage < 2 ? "Weiter" : "Los geht's")
                            .font(.obsBody.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OBSSpacing.lg)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, OBSSpacing.xxl)

                    if currentPage < 2 {
                        Button("Überspringen") {
                            onComplete()
                        }
                        .font(.obsFootnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, OBSSpacing.xxxl)
            }
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: OBSSpacing.md) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.obsAccentV2 : Color(.tertiarySystemFill))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPageView(
            icon: "bicycle",
            iconColor: .obsAccentV2,
            title: "Willkommen bei OBS Recorder",
            subtitle: "Erfasse Überholabstände mit deinem OpenBikeSensor und dokumentiere die Sicherheit auf deinen Radwegen."
        )
    }

    private var sensorPage: some View {
        OnboardingPageView(
            icon: "dot.radiowaves.left.and.right",
            iconColor: .obsGoodV2,
            title: "Sensor verbinden",
            subtitle: "Aktiviere Bluetooth auf deinem iPhone. Der Sensor verbindet sich automatisch, sobald er eingeschaltet ist."
        )
    }

    private var recordPage: some View {
        OnboardingPageView(
            icon: "record.circle.fill",
            iconColor: .obsDangerV2,
            title: "Aufnahme starten",
            subtitle: "Tippe auf den roten Button, um deine Fahrt aufzuzeichnen. Alle Überholvorgänge werden automatisch gespeichert."
        )
    }
}

// MARK: - Page View

private struct OnboardingPageView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: OBSSpacing.xxl) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(iconColor)
                .padding(.bottom, OBSSpacing.lg)

            VStack(spacing: OBSSpacing.lg) {
                Text(title)
                    .font(.obsScreenTitle)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.obsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, OBSSpacing.xxl)

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView {
        print("Onboarding complete")
    }
}
