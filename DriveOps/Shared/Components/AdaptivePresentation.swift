//
//  AdaptivePresentation.swift
//  DriveOps
//
//  Full-screen on iPad, sheet on iPhone.
//

import SwiftUI

extension View {
    func adaptivePresentation<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(AdaptivePresentationModifier(isPresented: isPresented, presentedContent: content))
    }
}

private struct AdaptivePresentationModifier<PresentedContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let presentedContent: () -> PresentedContent
    @Environment(\.horizontalSizeClass) private var hSizeClass

    func body(content: Content) -> some View {
        #if os(iOS)
        if hSizeClass == .regular {
            content.fullScreenCover(isPresented: $isPresented, content: presentedContent)
        } else {
            content.sheet(isPresented: $isPresented, content: presentedContent)
        }
        #else
        content.sheet(isPresented: $isPresented, content: presentedContent)
        #endif
    }
}
