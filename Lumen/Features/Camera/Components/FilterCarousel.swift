import SwiftUI

struct FilterCarousel: View {
    @Binding var selection: FilterKind

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterKind.allCases) { filter in
                        chip(for: filter)
                            .id(filter)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selection) { _, new in
                withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func chip(for filter: FilterKind) -> some View {
        let isSelected = filter == selection
        return Button {
            selection = filter
        } label: {
            Text(filter.displayName.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(isSelected ? Color.black : .white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : .white.opacity(0.08), in: Capsule())
        }
        .accessibilityLabel("\(filter.displayName) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct IntensitySlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            Slider(value: $value, in: 0...1)
                .tint(.accentColor)
            Text("\(Int((value * 100).rounded()))")
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter intensity")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.1, 1)
            case .decrement: value = max(value - 0.1, 0)
            @unknown default: break
            }
        }
    }
}
