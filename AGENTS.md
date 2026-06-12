# kurl iOS

kurl 블로그의 네이티브 iOS 앱. **iOS 27 이상 전용**, SwiftUI, ko/ja.
웹 프론트의 "조용한 웹로그"(§10)와 같은 영혼, 다른 몸 — 아래 디자인 언어가 이 레포의 SSOT다.

## 1. 디자인 언어 — "종이 본문, 액체 크롬"

웹에서 조용함의 답은 flat이었다. iOS에서 flat은 조용한 게 아니라 웹뷰처럼 보인다.
iOS 27의 답은 Liquid Glass 극대화 — 단, 유리가 **어디에 사는지** 안다:

- **종이 세계 (콘텐츠)** — 글 본문·목록 행·카드·타이포. slate 팔레트, hairline, 그린 한 가닥.
  여기에 유리를 바르지 않는다. 읽기는 §10 그대로 조용하다.
- **유리 세계 (크롬)** — 콘텐츠 위에 *떠 있는* 모든 것. 탭바·소스 스위처·인게이지 독·
  FAB·툴바·토스트·캡슐 컨트롤·시트. 전부 Liquid Glass, 예외 없이.
- 콘텐츠는 항상 유리 밑으로 흐른다 — edge-to-edge + `scrollEdgeEffectStyle(.soft)`.
  유리는 뒤에 흐르는 것이 있을 때만 유리다.

### 규칙

1. 유리는 떠 있는 것에만. 본문 텍스트·읽기 면에 `glassEffect` ❌ (Apple 레이어 모델).
2. 유리 위 글자/심볼은 시맨틱 스타일(`.primary`/`.secondary`)로 — vibrancy가 가독을 만든다.
   slate 고정색을 유리 위에 쓰지 않는다.
3. 그린 위계의 유리 번역(§10.3 등가): 흰 라벨을 받는 유리 = `.tint(Palette.accentFill)`(700).
   유리 위 active 아이콘/텍스트 = `Palette.link`. 비텍스트 마커 = `Palette.accent`(600).
4. 유리 위에 유리 ❌. 한 영역에 유리가 둘 이상이면 `GlassEffectContainer`로 묶는다 —
   가까워지면 녹아 붙고(blend), 상태 전환은 `glassEffectID`로 모핑한다.
5. 스크롤 콘텐츠 *안쪽*의 유리는 최소화(성능·소음). 카드 내부는 종이 문법 유지.
   유일한 예외: 커버 카드의 하단 타이포 띠 = `Glass.clear` (정적 이미지 위 1장).
6. 모션은 §10.7 그대로 "조용하지만 살아 있게" — snappy 0.2~0.3, reduce-motion이면 모핑·바운스 끔.
7. iOS 27 사용자 투명도 슬라이더를 존중한다: 유리가 불투명해져도 성립하는 위계
   (아이콘 weight·라벨·그린 한 가닥)를 유리 안에 항상 갖춘다.

### 표면 매핑

| 표면 | 처리 |
| --- | --- |
| 탭바 | 시스템 유리 + `.tabBarMinimizeBehavior(.onScrollDown)` 유지. 5탭 아이콘-온리 |
| 피드 소스 전환 | 떠 있는 유리 캡슐 세그먼트(`GlassSourceSwitcher`) — 상단 고정 스트립 ❌ |
| 글 좋아요·북마크 | 떠 있는 유리 독(`EngagementDock`, 우하단) — 단독·덱 임베드 동일 문법, 인라인 줄 금지. 글 끝에선 materialize 후퇴(스크롤 불가한 짧은 글은 유지) |
| 댓글 | 본문 끝 인라인 한 곳(덱=접힌 행) — 독·툴바에 댓글 진입을 중복시키지 않는다 |
| 글쓰기 새 글 | 유리 FAB(`.glassProminent` + accentFill 틴트) |
| 팔로우/구독 | 주행동(팔로우 전) = 그린 유리 캡슐, 완료 상태 = 맑은 유리(가라앉음) — `glassCapsule(prominent:)` |
| 로그인 CTA | 종이 위 = 그린 유리 캡슐. 유리 패널 *안*이면 솔리드 그린 캡슐(§1.4 유리 중첩 금지) |
| 토스트 | 유리 캡슐 |
| 분석 정렬 칩 | 유리 칩 클러스터(컨테이너로 blend) |
| 컴포즈 툴바 | `ToolbarSpacer`로 [저장·발행]·[⋯] 핀 분리, 발행 = `.glassProminent` |
| 에디터 | 캔버스·메타 입력은 종이. 유리는 크롬만 — 키보드 위 스니펫 바(`MarkdownSnippetBar`, 표준 md·커서 기준 삽입)와 시리즈·커버 칩. 터치 타깃 44pt 유지(좁으면 캡슐이 가로 스크롤) |
| 시트(2FA·예약·리비전) | 시스템 유리 그대로 |
| 커버 카드 | 하단 타이포 띠 = `Glass.clear` + 옅은 안전 스크림 |
| 태그 칩·목록 행·텍스트 카드 | 종이 유지 — 유리 ❌ |

### 폴리시 (예쁨의 규칙 — 더하기 전에 여기 맞는지)

- 카드: 모서리 20 연속 곡률(하단 유리 띠와 동일 값 강제). 라이트 = 무보더 + 이중 그림자
  (접촉 1.5 + 앰비언트 18), 다크 = slate 보더 유지(그림자가 죽는다). press 는 스프링 0.975.
- 안개(`BrandMist`)가 서는 곳 = **계정 · 피드 상단 · 검색 idle, 세 곳뿐**. 안개는 유리가
  굴절할 배경을 만드는 장치지 장식이 아니다 — 더 늘리지 말 것.
- 입장 모션: 피드·검색 카드 첫 8장만 `QuietAppear` 스태거(0.04s 간격, 7pt 상승).
  그 아래는 지연 없음(스크롤로 만나는 카드를 기다리게 하지 않는다). reduce-motion = 전부 정지.
- 타이포: 제목류만 tracking −0.2~−0.4(한글 과밀 주의, 본문은 손대지 않는다). 아바타는
  0.5px hairline 링. 스플래시 → 본 화면은 1.5% 스케일 착지 한 호흡.
- 빈 상태는 행동 가능해야 한다 — 검색 대기 = 최근 검색·인기 태그·작가(장식 일러스트 ❌).
  글의 끝도 막다른 길 금지 — 작가 카드 + 팔로우 + 다른 글이 선다.
- 칩처럼 보이면 칩처럼 눌린다: 카드 태그칩 = 태그 피드, 카드 길게 누르면 좋아요·북마크·
  작가·공유(컨텍스트 메뉴, 멱등 "켜기"). browse 시간 표기 = 상대시간, 상세만 절대 날짜.

## 2. 깨지 말 것

- 탭바: 5탭 아이콘-온리, minimize 동작 — `TabBarMinimizeUITests`가 프레임 폭으로 가드.
- `NavigationStack`에 path 바인딩 ❌ — tabBarMinimizeBehavior가 죽는다(시스템 버그).
- 읽기 컬럼 672(`Metrics.readingColumn`), Dynamic Type 상한 `accessibility2`.
- 제목 세리프 ❌. 브랜드 그린 #059669 외 단독 색 ❌. 터치 타깃 44pt(`expandTapTarget`).
- 페이지형 TabView 중첩 ❌ — Liquid Glass가 활성 스크롤뷰를 못 찾는다(FeedView 주석).

## 3. 빌드·검증 (iOS 27)

- 툴체인: Xcode 27 베타 — `DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer`.
  배포 타깃 27.0. 시뮬 기준 디바이스 `kurl-air-27`(iPhone Air, 27.0 런타임) — GUI 는
  stable Xcode 의 Simulator.app 사용(27 베타엔 Simulator.app 미포함).
- 검증 진입로(DEBUG): `--mocks`, `--tab write|discover|search|account`,
  `--open analytics|compose|notifications`, `--post user/slug`, `--selftest`.
- UI 테스트: `xcodebuild test -scheme kurl` (DiscoverDeck·TabBarMinimize).
  26.0 런타임은 minimize 자체가 깨져 skip — 27 디바이스에서 단정한다.
- 27-only API 채택 현황: `GlassEffectTransition.materialize`(독 등장),
  `ConcentricRectangle`(코어 승격) — 독·FAB 쉐이프. `DepthAlignment` 계열은 미채용.
