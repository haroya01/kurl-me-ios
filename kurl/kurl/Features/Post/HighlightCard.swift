import SwiftUI

struct HighlightCardLayer: View {
    let store: PostHighlightStore
    let card: PostHighlightStore.Card
    let shareURL: (HighlightView) -> URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardHeight: CGFloat = 0
    @State private var confirmDelete: HighlightView?

    private let gap: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let anchor = card.anchor.offsetBy(dx: -frame.minX, dy: -frame.minY)
            let width = min(geo.size.width - Metrics.gutter * 2, 360)
            let x = min(max(anchor.midX - width / 2, Metrics.gutter), geo.size.width - Metrics.gutter - width)
            let roomAbove = anchor.minY - geo.safeAreaInsets.top
            let y = roomAbove > cardHeight + gap + 8
                ? anchor.minY - gap - cardHeight
                : anchor.maxY + gap
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                HighlightCard(
                    store: store, highlights: store.cardHighlights(card), shareURL: shareURL,
                    onClose: close, onDelete: delete)
                    .frame(width: width)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                    .offset(x: x, y: y)
                    .opacity(cardHeight == 0 ? 0 : 1)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .alert("이 하이라이트를 지울까요?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("지우기", role: .destructive) {
                if let target = confirmDelete { remove(target) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("남긴 공개 메모와 답글도 함께 사라져요. 되돌릴 수 없어요.")
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { store.card = nil }
    }

    private func delete(_ highlight: HighlightView) {
        if HighlightPaint.hasThread(highlight) {
            confirmDelete = highlight
        } else {
            remove(highlight)
        }
    }

    private func remove(_ highlight: HighlightView) {
        close()
        Task {
            if await store.delete(id: highlight.id) {
                ToastCenter.shared.show(String(localized: "하이라이트를 지웠어요"))
            } else {
                ToastCenter.shared.show(String(localized: "지우지 못했어요. 다시 시도해 주세요"))
            }
        }
    }
}

struct HighlightCard: View {
    let store: PostHighlightStore
    let highlights: [HighlightView]
    let shareURL: (HighlightView) -> URL?
    let onClose: () -> Void
    let onDelete: (HighlightView) -> Void

    @ScaledMetric(relativeTo: .footnote) private var unit: CGFloat = 1

    private var mine: HighlightView? { highlights.first(where: store.isMine) }
    private var conversations: [HighlightView] { highlights.filter(HighlightPaint.hasThread) }
    private var lead: HighlightView? { mine ?? highlights.first }

    private var readers: [Author] {
        var seen = Set<Int64>()
        return highlights.compactMap { h in
            guard !store.isMine(h), let author = h.author, seen.insert(author.id).inserted else { return nil }
            return author
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if conversations.isEmpty {
                Button {
                    open(lead)
                } label: {
                    Text("이 문장에 대해 이야기하기")
                        .typeScale(.footnote)
                        .foregroundStyle(Palette.link)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("highlightCard.talk")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(conversations.prefix(2)) { conversation in
                        conversationRow(conversation)
                    }
                }
            }
            Hairline()
            actions
        }
        .padding(16)
        .background(Palette.readingBg, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Palette.hairline))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("highlightCard")
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: -6) {
                ForEach(readers.prefix(3)) { author in
                    AvatarView(author: author, size: 20 * unit)
                        .overlay(Circle().strokeBorder(Palette.readingBg, lineWidth: 1.5))
                }
            }
            .accessibilityHidden(true)
            summary
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Label("공개", systemImage: "globe")
                .labelStyle(.iconOnly)
                .font(.system(size: 12 * unit))
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel(Text("모두에게 공개된 하이라이트"))
        }
    }

    private var summary: Text {
        let others = readers.count
        if mine != nil {
            return others == 0 ? Text("내가 하이라이트했어요") : Text("나 외 \(others)명이 하이라이트했어요")
        }
        if others == 1, let only = readers.first {
            return Text("\(only.username)님이 하이라이트했어요")
        }
        return Text("\(others)명이 하이라이트했어요")
    }

    private func conversationRow(_ highlight: HighlightView) -> some View {
        Button {
            open(highlight)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let note = highlight.note, !note.isEmpty {
                    Text(note)
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    (store.isMine(highlight) ? Text("나") : Text(verbatim: highlight.author?.username ?? ""))
                        .fontWeight(.semibold)
                    if highlight.replyCount > 0 {
                        Text("답글 \(highlight.replyCount)")
                    }
                    Spacer(minLength: 0)
                    Text("대화 보기")
                        .foregroundStyle(Palette.link)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * unit, weight: .semibold))
                        .foregroundStyle(Palette.link)
                }
                .typeScale(.meta)
                .foregroundStyle(Palette.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("highlightCard.conversation.\(highlight.id)")
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if let lead, let url = shareURL(lead) {
                ShareLink(item: url, message: Text("“\(lead.quote)”")) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
            }
            if let lead, lead.id > 0, AuthStore.shared.isSignedIn {
                Button {
                    onClose()
                    store.connectTarget = lead
                } label: {
                    Label("컬렉션", systemImage: "rectangle.stack.badge.plus")
                }
                .accessibilityLabel(Text("컬렉션에 연결"))
                .accessibilityIdentifier("highlightCard.connect")
            }
            Spacer(minLength: 0)
            if let mine {
                Button(role: .destructive) {
                    onDelete(mine)
                } label: {
                    Text("지우기")
                }
                .foregroundStyle(Palette.danger)
                .accessibilityLabel(Text("하이라이트 지우기"))
                .accessibilityIdentifier("highlightCard.delete")
            }
        }
        .labelStyle(.titleAndIcon)
        .typeScale(.footnote)
        .foregroundStyle(Palette.ink)
        .buttonStyle(.plain)
    }

    private func open(_ highlight: HighlightView?) {
        guard let highlight else { return }
        onClose()
        store.threadHighlightId = highlight.id
    }
}
