//
//  ConnectSheet.swift
//  kurl
//
//  "연결" — §0의 동사. 글/하이라이트/노트를 컬렉션에 잇는다(broadcast 아님).
//  2단계 뎁스: ① 어디에 남길까요(컬렉션 고르기) → ② 추가(왜 한 줄 + 확정).
//  "왜 한 줄"이 단순 북마크와 컬렉션을 가르는 영혼이라, 고른 뒤의 집중된 한 순간으로 둔다.
//

import SwiftUI

struct ConnectSheet: View {
    let targetKind: LocalizedStringKey
    let targetTitle: String
    let blockType: ConnectionBlockKind
    let refId: Int64

    /// "왜 이었나요" 한 줄의 글자 상한 — 백엔드 연결 why 캡과 같은 값(한 줄 이유이지 본문이 아니다).
    private static let whyLimit = 280

    @State private var why = ""
    @State private var selected: Set<Int64> = []
    @State private var collections: [CollectionSummary] = []
    /// 이 대상이 이미 연결된 컬렉션 — collectionId → connectionId. 로드 때 summary.connectionId 로
    /// 채워지고, 해제하면 그 항목을 지워 행이 다시 고를 수 있는 상태로 돌아간다(서버 재조회 없이 낙관).
    @State private var connectedIds: [Int64: Int64] = [:]
    /// 지금 해제 요청이 나가 있는 컬렉션 — 그 행의 "해제"를 잠깐 진행 중으로 그린다(연타 방지).
    @State private var disconnecting: Set<Int64> = []
    @State private var loading = true
    @State private var failed = false
    @State private var saving = false
    @State private var showCreate = false
    /// 성공 햅틱 트리거 — 만들기·연결이 끝나면 +1(§10 살아 있는 절제).
    @State private var didConnect = 0
    @State private var didCreate = 0
    /// 해제 성공 햅틱(가벼운 임팩트) — 연결과 결이 다른 되돌림이라 별도 트리거.
    @State private var didDisconnect = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1
    @ScaledMetric(relativeTo: .footnote) private var metaUnit: CGFloat = 1

    var body: some View {
        NavigationStack {
            step1
                .navigationTitle("어디에 남길까요?")
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .background(Palette.readingBg)
        .sheet(isPresented: $showCreate) {
            CreateCollectionSheet { created in
                collections.insert(created, at: 0)
                selected.insert(created.id)
                didCreate += 1
            }
        }
        .sensoryFeedback(.success, trigger: didConnect)
        .sensoryFeedback(.success, trigger: didCreate)
        .sensoryFeedback(.impact(weight: .light), trigger: didDisconnect)
        .task { await loadCollections() }
    }

    private func loadCollections() async {
        failed = false
        do {
            // 이 대상이 어느 컬렉션에 이미 담겼는지 함께 받는다 — 담긴 곳은 "연결됨"으로 표시·해제한다.
            collections = try await CollectionsAPI.mine(blockType: blockType, refId: refId)
            connectedIds = Dictionary(
                uniqueKeysWithValues: collections.compactMap { c in
                    c.connectionId.map { (c.id, $0) }
                })
            loading = false
        } catch {
            loading = false
            // 빈 계정과 헷갈리지 않게 — 못 읽었으면 "다시 시도"를 띄운다(형제 failedState).
            if collections.isEmpty { failed = true }
        }
    }

    /// 이미 담긴 컬렉션에서 이 대상을 뺀다 — 낙관 없이 서버 성공 뒤에 행을 미연결로 되돌린다(되돌림은
    /// 연결보다 드물고, 실패 시 "연결됨"이 잠깐 사라졌다 돌아오면 더 혼란스럽다).
    private func disconnect(_ collectionId: Int64) async {
        guard let connectionId = connectedIds[collectionId] else { return }
        disconnecting.insert(collectionId)
        defer { disconnecting.remove(collectionId) }
        do {
            try await CollectionsAPI.disconnect(
                collectionId: collectionId, connectionId: connectionId)
            _ = withAnimation(.snappy(duration: 0.2)) {
                connectedIds.removeValue(forKey: collectionId)
            }
            didDisconnect += 1
        } catch {
            ToastCenter.shared.show(String(localized: "연결을 끊지 못했습니다"))
        }
    }

    // MARK: ① 어디에 남길까요 — 컬렉션 고르기

    private var step1: some View {
        VStack(spacing: 0) {
            if loading {
                KurlLoadingMark()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                failedState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(collections) { c in
                            collectionRow(c)
                            Hairline()
                        }
                        newCollectionRow
                        newPathRow
                    }
                }
                .scrollIndicators(.hidden)
            }
            if !failed { nextButton }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
    }

    private var failedState: some View {
        ErrorState(retry: { Task { loading = true; await loadCollections() } })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nextButton: some View {
        // 유리는 라벨이 아니라 버튼 바깥, 라벨엔 contentShape — 유리를 라벨 안에 두면 캡슐의
        // 여백부가 히트테스트에서 빠져 "안 눌리는 버튼"이 된다(구독 캡슐과 같은 검증된 문법).
        NavigationLink {
            step2
        } label: {
            Text(selected.isEmpty ? "컬렉션을 골라주세요" : "다음")
                .typeScale(.titleSmall)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(prominent: true)
        .disabled(selected.isEmpty)
        .opacity(selected.isEmpty ? 0.5 : 1)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func collectionRow(_ c: CollectionSummary) -> some View {
        // 이미 담긴 컬렉션은 고르는 행이 아니라 "연결됨 + 해제" 행 — 실수로 또 담지 않게 선택 자체를 막는다.
        if connectedIds[c.id] != nil {
            HStack(spacing: 12) {
                rowMeta(c)
                Spacer(minLength: 0)
                connectedControls(c)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        } else {
            Button {
                if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
            } label: {
                HStack(spacing: 12) {
                    rowMeta(c)
                    Spacer(minLength: 0)
                    Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20 * unit))
                        .foregroundStyle(selected.contains(c.id) ? Palette.accent : Palette.faint)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
        }
    }

    /// 행 왼쪽 — 제목 · 미리보기 한 줄 · 메타(길·공개범위·개수). 선택 행과 연결됨 행이 함께 쓴다.
    private func rowMeta(_ c: CollectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(c.title)
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            // 안에 뭐가 들었는지 한 줄 — 어디 넣을지 떠올리게. 비었으면 개수만.
            if !c.preview.isEmpty {
                Text(c.preview.joined(separator: " · "))
                    .typeScale(.lede)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            HStack(spacing: 5) {
                if c.kind == .path {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10 * metaUnit, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    Text("길")
                        .foregroundStyle(Palette.accent)
                    Text("·")
                }
                Image(systemName: c.visibility.icon)
                    .font(.system(size: 10 * metaUnit, weight: .medium))
                Text("\(c.count)개")
            }
            .typeScale(.meta)
            .foregroundStyle(Palette.faint)
        }
    }

    /// 이미 담긴 행의 우측 — "연결됨" 표식 + "해제" 버튼. 선택 원 자리를 대신한다(§10 조용히, 종이 문법).
    private func connectedControls(_ c: CollectionSummary) -> some View {
        HStack(spacing: 10) {
            // "연결됨" = 조용한 초록 한 점(비텍스트 마커라 §10.3 accent 허용) + 라벨.
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13 * metaUnit, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel(Text("연결됨"))
                // 접근성 크기에선 "연결됨"이 두 줄로 쪼개져 "해제"에 붙는다 — 초록 체크가
                // 이미 상태를 말하므로 라벨은 접고 마커만 남긴다(VoiceOver 는 위 라벨로 유지).
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("연결됨")
                        .typeScale(.meta)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            Button {
                Task { await disconnect(c.id) }
            } label: {
                Group {
                    if disconnecting.contains(c.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("해제")
                            .font(.system(size: 13 * unit, weight: .semibold))
                            .foregroundStyle(Palette.link)
                    }
                }
                .frame(minWidth: 44, minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disconnecting.contains(c.id))
            .accessibilityLabel(Text("\(c.title) 연결 해제"))
        }
    }

    private var newCollectionRow: some View {
        Button {
            showCreate = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14 * unit, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 22)
                Text("새 컬렉션 만들기")
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    /// 새 길(PATH) 만들기 — 순서로 엮는 reading path. 문장을 가로질러 하나의 흐름으로.
    private var newPathRow: some View {
        Button {
            Task { await createPathAndSelect() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 14 * unit, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 22)
                Text("새 길 만들기")
                    .typeScale(.titleSmall)
                    .foregroundStyle(Palette.ink)
                Text("순서로 엮기")
                    .typeScale(.meta)
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    // MARK: ② 추가 — 왜 한 줄 + 확정

    private var step2: some View {
        VStack(alignment: .leading, spacing: 0) {
            targetPreview.padding(.top, 18)

            // "왜"가 자기 화면을 얻는다 — 고른 뒤의 집중된 한 순간(§0 큐레이션 영혼).
            Text("왜 이었나요")
                .typeScale(.eyebrow)
                .tracking(0.4)
                .foregroundStyle(Palette.faint)
                .padding(.top, 24)
                .padding(.bottom, 10)
            whyField

            Text("\(selected.count)개 컬렉션에 추가됩니다.")
                .typeScale(.footnote)
                .foregroundStyle(Palette.secondary)
                .padding(.top, 12)

            Spacer(minLength: 0)
            addButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 16)
        .navigationTitle("추가")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var targetPreview: some View {
        HStack(spacing: 8) {
            Text(targetKind)
                .font(.system(size: 11 * metaUnit, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Palette.secondary)
            Text(targetTitle)
                .typeScale(.titleSmall)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var whyField: some View {
        // 회색 채움 박스 대신 밑줄 한 줄 — 입력이되 종이 위에 글자가 그대로 앉는다.
        VStack(alignment: .leading, spacing: 9) {
            TextField("한 줄 (선택)", text: $why, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16 * unit))
                .foregroundStyle(Palette.ink)
                // 상한을 넘겨 붙여넣거나 IME 로 밀어 넣어도 그 자리에서 자른다(백엔드 캡과 같은 값).
                .onChange(of: why) { _, new in
                    if new.count > Self.whyLimit {
                        why = String(new.prefix(Self.whyLimit))
                    }
                }
            Hairline()
            // 남은 여백처럼 조용한 카운터 — 우측 정렬 meta. 다 차면 초록으로 한계를 알린다(§10 조용히).
            Text("\(why.count)/\(Self.whyLimit)")
                .typeScale(.meta)
                .foregroundStyle(why.count >= Self.whyLimit ? Palette.link : Palette.faint)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(Text("\(why.count)자 입력, 최대 \(Self.whyLimit)자"))
        }
    }

    private var addButton: some View {
        Button {
            Task { await connectAll() }
        } label: {
            Group {
                if saving { ProgressView().tint(.white) } else { Text("추가") }
            }
            .typeScale(.titleSmall)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(prominent: true)
        .disabled(saving || selected.isEmpty)
        .opacity(selected.isEmpty ? 0.5 : 1)
        .padding(.top, 12)
    }

    // MARK: 동작

    /// 새 길(PATH) 만들기 — 길은 타깃 글을 첫 마디로 출발하니 그 제목을 시작 이름으로.
    private func createPathAndSelect() async {
        let name = targetTitle.isEmpty ? String(localized: "새 길") : targetTitle
        guard let created = try? await CollectionsAPI.create(
            title: name, description: nil, visibility: .private, kind: .path)
        else {
            ToastCenter.shared.show(String(localized: "만들지 못했습니다"))
            return
        }
        collections.insert(created, at: 0)
        selected.insert(created.id)
        didCreate += 1
    }

    private func connectAll() async {
        saving = true
        defer { saving = false }
        let line = why.trimmingCharacters(in: .whitespacesAndNewlines)
        var stillFailing: Set<Int64> = []
        for collectionId in selected {
            do {
                try await CollectionsAPI.connect(
                    collectionId: collectionId, blockType: blockType, refId: refId,
                    why: line.isEmpty ? nil : line)
            } catch {
                stillFailing.insert(collectionId)
            }
        }
        if stillFailing.isEmpty {
            didConnect += 1
            ToastCenter.shared.show(String(localized: "추가했어요"))
            dismiss()
            return
        }
        // 일부만 실패 — 시트를 닫지 않고 실패한 컬렉션과 쓴 "왜"를 그대로 둔다(다시 시도).
        selected = stillFailing
        ToastCenter.shared.show(String(localized: "일부 연결에 실패했습니다"))
    }
}
