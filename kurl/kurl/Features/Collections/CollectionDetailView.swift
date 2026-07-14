//
//  CollectionDetailView.swift
//  kurl
//
//  컬렉션 상세 = 연결된 블록(글·하이라이트·노트)이 섞여 흐르는 채널. 각 연결은 큐레이터의 한 줄
//  이유를 단다 — 단순 북마크와 컬렉션을 가르는 영혼. 백엔드 `GET /collections/{id}`.
//

import SwiftUI

struct CollectionDetailView: View {
    let collectionId: Int64
    @State private var detail: CollectionDetail?
    // 연결 목록은 detail 에서 떼어 따로 둔다 — 끊기를 낙관(즉시 제거)하고 실패 시 되돌리기 위해.
    @State private var connections: [ConnectionItem] = []
    // 이 컬렉션을 엮은 큐레이터와 취향이 겹치는(같은 것을 엮은) 사람들 — 팔로우 아닌 큐레이션으로 잇는 발견.
    @State private var kindred: [KindredCurator] = []
    @State private var disconnects = 0
    @State private var loading = true
    @State private var failed = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showReorder = false
    // 길 이어읽기 기억(기기 로컬) — 스텝을 열면 여기 도달 index 가 오르고, @Observable 이라
    // 돌아오면 현재 스텝 강조·진행률·연속성 바가 곧바로 갱신된다. 서버 0.
    @State private var resume = PathResumeStore.shared
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    /// 내 컬렉션일 때만 수정·삭제·끊기 — 남의 공개 컬렉션은 보기만.
    private var isOwner: Bool {
        detail?.curatorUsername != nil && detail?.curatorUsername == AuthStore.shared.me?.username
    }

    /// 길(순서 있는 읽기 여정)인지 — 삭제 확인 문구를 "컬렉션"과 "길"로 가른다(툴바와 같은 분기).
    private var isPath: Bool { detail?.kind == .path }

    /// "취향이 겹치는 큐레이터"를 보일지 — 비공개거나 아직 아무것도 안 담긴 컬렉션엔 겹칠 취향이 없다.
    /// 빈·비공개 상세에 남 추천이 뜨면 "왜 여기 있지" 하는 잡음이라, 그런 표면엔 아예 렌더하지 않는다.
    private var showsKindred: Bool {
        !kindred.isEmpty && !connections.isEmpty && detail?.visibility != .private
    }

    var body: some View {
        ReadingColumn(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if let detail {
                header(detail)
                Hairline().padding(.bottom, 4)
                if detail.kind == .path {
                    // PATH = reading path. 리스트가 아니라 순번으로 잇는 가이드 워크(문장→왜→문장).
                    pathWalk()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(connections.enumerated()), id: \.element.id) {
                            index, item in
                            connectionCell(item)
                                .modifier(QuietAppear(index: index))
                            if index < connections.count - 1 {
                                Hairline().padding(.leading, 14)
                            }
                        }
                    }
                }
                if connections.isEmpty {
                    emptyState
                }
                if showsKindred {
                    kindredSection()
                }
            } else if failed {
                failedState
            }
        }
        .navigationTitle(detail?.title ?? String(localized: "컬렉션"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Route.self) { RouteView(route: $0) }
        .toolbar {
            if isOwner, let detail {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEdit = true
                        } label: {
                            Label("수정", systemImage: "pencil")
                        }
                        if detail.kind == .path, connections.count > 1 {
                            Button {
                                showReorder = true
                            } label: {
                                Label("순서 편집", systemImage: "arrow.up.arrow.down")
                            }
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(detail.kind == .path ? "길 삭제" : "컬렉션 삭제", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.brand)
                    .accessibilityLabel(Text("컬렉션 관리"))
                    // detail 변화에 메뉴가 최신 값을 쓰도록 id 고정.
                    .id(detail.id)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let detail {
                EditCollectionSheet(
                    id: detail.id, kind: detail.kind, initialTitle: detail.title,
                    initialBlurb: detail.blurb, initialVisibility: detail.visibility
                ) { Task { await load() } }
            }
        }
        .sheet(isPresented: $showReorder) {
            if let detail {
                PathReorderSheet(detail: detail) { Task { await load() } }
            }
        }
        .alert(isPath ? "이 길을 삭제할까요?" : "이 컬렉션을 삭제할까요?", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) { Task { await deleteCollection() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text(isPath
                ? "엮은 순서와 연결이 함께 사라져요. 연결된 글·노트 자체는 지워지지 않아요."
                : "담긴 연결도 함께 사라져요. 연결된 글·노트 자체는 지워지지 않아요.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: disconnects)
        .task { await load() }
    }

    /// 끊기는 낙관 — 즉시 빼고(점프·지연 없이) 실패하면 자리째 되돌린다. reload 없음.
    private func disconnect(_ item: ConnectionItem) async {
        guard let idx = connections.firstIndex(where: { $0.id == item.id }) else { return }
        let snapshot = connections
        _ = withAnimation(.snappy(duration: 0.25)) {
            connections.remove(at: idx)
        }
        do {
            try await CollectionsAPI.disconnect(collectionId: collectionId, connectionId: item.id)
            disconnects += 1
        } catch {
            withAnimation(.snappy(duration: 0.25)) { connections = snapshot }
            ToastCenter.shared.show(String(localized: "연결을 끊지 못했습니다"))
        }
    }

    private func deleteCollection() async {
        do {
            try await CollectionsAPI.delete(id: collectionId)
            dismiss()
        } catch {
            ToastCenter.shared.show(String(localized: "컬렉션을 삭제하지 못했습니다"))
        }
    }

    private func load() async {
        failed = false
        do {
            let fresh = try await CollectionsAPI.detail(id: collectionId)
            detail = fresh
            connections = fresh.connections
            loading = false
            if let username = fresh.curatorUsername {
                kindred = (try? await CollectionsAPI.kindredCurators(username: username)) ?? []
            }
        } catch {
            loading = false
            if detail == nil { failed = true }
        }
    }

    // MARK: 취향이 겹치는 큐레이터 — 같은 것을 엮은 사람들로 잇는 발견(connect not broadcast)

    private func kindredSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline().padding(.vertical, 8)
            Text("취향이 겹치는 큐레이터")
                .typeScale(.eyebrow)
                .tracking(0.4)
                .foregroundStyle(Palette.faint)
                .padding(.bottom, 6)
            ForEach(Array(kindred.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: Route.author(username: item.curator.username)) {
                    kindredRow(item)
                }
                .buttonStyle(.plain)
                if index < kindred.count - 1 {
                    Hairline().padding(.leading, 55)
                }
            }
        }
        .padding(.top, 8)
    }

    private func kindredRow(_ item: KindredCurator) -> some View {
        HStack(spacing: 11) {
            AvatarView(author: item.curator, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(item.curator.username)")
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let bio = item.curator.bio, !bio.isEmpty {
                    Text(bio)
                        .typeScale(.lede)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("\(item.sharedItems)개 함께 엮음")
                .typeScale(.meta)
                .foregroundStyle(Palette.faint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: 헤더

    private func header(_ detail: CollectionDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.title)
                .typeScale(.featured)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let blurb = detail.blurb {
                Text(blurb)
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if let curator = detail.curatorUsername {
                    AvatarView(
                        author: Author(id: 0, username: curator, bio: nil, avatarUrl: nil), size: 20)
                    Text(curator).foregroundStyle(Palette.ink)
                    Text("·").foregroundStyle(Palette.faint)
                }
                Image(systemName: detail.visibility.icon)
                    .font(.system(size: 11 * metaUnit, weight: .medium))
                Text(detail.visibility.label)
                Text("·").foregroundStyle(Palette.faint)
                Text("\(connections.count)개")
                // 길이면 진행률 한 조각 — "목록"이 아니라 "읽어 내려가는 것"이라는 신호.
                if detail.kind == .path, let reached = readReached, reached > 0 {
                    Text("·").foregroundStyle(Palette.faint)
                    Text("\(reached) / \(connections.count) 읽음")
                        .foregroundStyle(Palette.link)
                        .fontWeight(.semibold)
                }
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.secondary)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }

    // MARK: 연결 한 칸 — 왼쪽 실(연결 신호) + [이유 한 줄] + 블록

    private func connectionCell(_ item: ConnectionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.hairlineStrong)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 9) {
                if let why = item.why {
                    Text(why)
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BlockPreview(block: item.block)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    Task { await disconnect(item) }
                } label: {
                    Label("연결 끊기", systemImage: "link.badge.plus")
                }
            }
        }
    }

    // MARK: 길(PATH) — 순번으로 잇는 가이드 워크. 큐레이터의 "왜"가 문장과 문장을 잇는 흐름.
    //        P2: "목록"이 아니라 "읽는 목적지" — 현재 스텝 강조 + 이어읽기 연속성 + 진행률.

    /// 이 스텝이 열어 읽을 수 있는 목적지인가(글·하이라이트만; 노트는 그 자리 텍스트). 있으면 그 경로.
    private func readableTarget(_ item: ConnectionItem) -> Route? {
        switch item.block {
        case let .post(_, _, username, slug, _):
            return .post(username: username, slug: slug)
        case let .highlight(quote, _, username, slug):
            return .postFocusQuote(username: username, slug: slug, quote: quote)
        case .note:
            return nil
        }
    }

    /// index 이후(포함) 처음으로 열어 읽을 수 있는 스텝 — 노트에 서면 그 자리엔 열 게 없으니 다음
    /// 글·하이라이트로 건너뛴다(연속성 바가 노트에서 헛도는 CTA 가 되지 않게). 없으면 nil.
    private func nextReadableStep(from index: Int) -> (step: Int, target: Route)? {
        guard index >= 0, index < connections.count else { return nil }
        for i in index..<connections.count {
            if let target = readableTarget(connections[i]) {
                return (i, target)
            }
        }
        return nil
    }

    /// 기기에 남은 "가장 멀리 걸은 스텝" index — 아직 아무 데도 안 걸었으면 nil.
    /// 연결이 빠지거나 재배치되면 저장된 index 가 현재 스텝 수를 넘어 "7 / 5 읽음" 같은 불가능한
    /// 진행률이 뜬다 — 렌더 시점에 현재 스텝 수로 클램프해 그런 값 자체를 못 만든다.
    private var furthestReached: Int? {
        guard !connections.isEmpty else { return nil }
        return resume.furthestStep(collectionId: collectionId).map { min($0, connections.count - 1) }
    }

    /// 몇 편까지 읽었나(진행률 숫자) — 도달 index + 1. 헤더 메타가 읽는다.
    private var readReached: Int? { furthestReached.map { $0 + 1 } }

    /// 지금 "여기서 이어 읽는" 스텝 — 가장 멀리 걸은 다음 칸(마지막까지 걸었으면 마지막). 아직 시작
    /// 전이면 첫 칸. 시작 전(0)에는 강조를 얹지 않아 첫 진입이 조용하다.
    private var currentStepIndex: Int? {
        guard !connections.isEmpty else { return nil }
        guard let reached = furthestReached else { return nil }  // 시작 전 = 강조 없음
        return min(reached + 1, connections.count - 1)
    }

    private func pathWalk() -> some View {
        let total = connections.count
        let current = currentStepIndex
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(connections.enumerated()), id: \.element.id) { index, item in
                pathStepCell(
                    index: index, total: total, item: item,
                    isCurrent: index == current,
                    // 현재 스텝까지는 초록 실이 흐른다(걸어온 길). 그 아래는 아직 회색.
                    threadFilled: current.map { index < $0 } ?? false)
                    .modifier(QuietAppear(index: index))
            }
        }
        .padding(.top, 4)
    }

    private func pathStepCell(
        index: Int, total: Int, item: ConnectionItem, isCurrent: Bool, threadFilled: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // 순번 노드 + 다음 문장으로 잇는 세로 선 — "걷는다"는 신호.
            // 순번 칩은 구조 신호일 뿐 — 초록은 주액션·데이터 전용이라 중립(잉크)으로 가라앉힌다(RailHeading 규율).
            // 예외: *현재 스텝* 하나만 초록 채움 — "지금 여기"라는 진행 데이터라 §10.3 초록 허용.
            VStack(spacing: 0) {
                Text("\(index + 1)")
                    .typeScale(.meta)
                    .fontWeight(.bold)
                    .foregroundStyle(isCurrent ? Color.white : Palette.heading)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isCurrent ? Palette.accentFill : Palette.hairlineStrong))
                if index < total - 1 {
                    // 걸어온 구간은 초록 한 올, 아직 안 걸은 구간은 회색.
                    Rectangle()
                        .fill(threadFilled ? Palette.accent : Palette.hairlineStrong)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let why = item.why {
                    // 큐레이터가 앞 문장에서 잇는 말 = 흐름의 목소리.
                    Text(why)
                        .typeScale(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BlockPreview(block: item.block)
                    // 카드로 스텝을 열어도 이어읽기 위치가 앞으로 — 연속성 바 탭과 같은 신호.
                    // (BlockPreview 는 공용 컴포넌트라 손대지 않고, 여기서 탭만 얹어 나란히 진행한다.)
                    .simultaneousGesture(TapGesture().onEnded {
                        if readableTarget(item) != nil {
                            resume.advance(collectionId: collectionId, toStep: index)
                        }
                    })
                if isCurrent {
                    // "지금 여기 · 이어서 읽기" — 목록을 목적지로 만드는 연속성 한 조각.
                    continuityBar(index: index, total: total)
                }
            }
            .padding(.bottom, index < total - 1 ? 24 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    Task { await disconnect(item) }
                } label: {
                    Label("이 문장 빼기", systemImage: "minus.circle")
                }
            }
        }
    }

    // MARK: 이어읽기 연속성 바 — "지금 여기 · N/M" + "이어서 N편 읽기" + 계속 → (초록 틴트, 종이 문법)

    @ViewBuilder
    private func continuityBar(index: Int, total: Int) -> some View {
        // 남은 편 수 — 이 칸 포함 끝까지. "이어서 N편 읽기"로 얼마나 남았는지 손에 잡힌다.
        let remaining = total - index
        // 이어 읽을 목적지 — 이 칸이 노트면 그 자리엔 열 게 없으니 다음 글·하이라이트로 건너뛴다.
        // 뒤로 노트만 남으면 nil — 이때는 탭 가능한 척하는 캡슐을 걷고 조용한 표식만 남긴다.
        let resumeStep = nextReadableStep(from: index)
        let bar = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("지금 여기 · \(index + 1) / \(total)")
                    .typeScale(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.link)
                Text(remaining > 1 ? "이어서 \(remaining)편 읽기" : "마지막 편 읽기")
                    .typeScale(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 8)
            // 흰 라벨을 받는 accent-700 캡슐 — §10.3 600/700 규칙(흰 글자엔 700).
            Text("계속 →")
                .typeScale(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Palette.accentFill))
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // 초록 틴트 종이 캡슐 — 유리 없이(§1) accent 를 옅게 실어 "지금 여기"를 데운다.
            RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                .fill(Palette.accent.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                        .strokeBorder(Palette.accent.opacity(0.22), lineWidth: 1))
        )
        .contentShape(Rectangle())

        if let resumeStep {
            // 탭 = 이어 읽을 편으로 들어간다(노트면 다음 글로 건너뛴 자리). 들어간 스텝은 걸은
            // 것으로 표시 — 다음 진입 시 그 다음 칸이 "지금 여기"가 된다.
            NavigationLink(value: resumeStep.target) { bar }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    resume.advance(collectionId: collectionId, toStep: resumeStep.step)
                })
                .accessibilityLabel(Text("이어서 읽기 · \(index + 1) / \(total)"))
        } else {
            // 뒤로 노트만 남았다 — 열 게 없으니 "지금 여기"만 조용히 표시(탭 가능한 캡슐 걷어냄).
            HStack(spacing: 6) {
                Text("지금 여기 · \(index + 1) / \(total)")
                    .typeScale(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.link)
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyState: some View {
        // 막다른 길 금지 — 빈 컬렉션은 이을 글을 찾으러 피드로 이어준다(다른 빈 면과 같은 언어).
        // 큐레이터 본인에겐 "어떻게 채우는지" 동사("잇기")를 가르친다 — 남에겐 그냥 비었다고만.
        FeedPlaceholder(
            eyebrow: "컬렉션",
            title: "아직 연결된 글이 없어요",
            message: isOwner
                ? "글이나 하이라이트에서 \"컬렉션에 잇기\"로 이 컬렉션에 이어 채워요."
                : "아직 담긴 글이 없어요.",
            actionTitle: "읽을 글 찾기",
            action: { TabRouter.shared.selection = 0 }
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var failedState: some View {
        ContentUnavailableView {
            Label("불러오지 못했습니다", systemImage: "wifi.exclamationmark")
        } actions: {
            Button("다시 시도") { Task { loading = true; await load() } }
                .foregroundStyle(Palette.link)
        }
        .padding(.top, 60)
    }
}
