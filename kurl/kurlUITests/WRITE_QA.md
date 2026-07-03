# 글쓰기 · 하이라이트 QA 매트릭스

작성 경험(컴포즈)과 리더 하이라이트를 **재실행 가능한 XCUITest 레인**으로 검사한다.
일회성 눈검증이 아니라, 기능마다 어떤 테스트가 무엇을 단정하는지 표로 묶어 회귀를 막는다.

## 레인 실행

```sh
DEVELOPER_DIR=/Applications/Xcode-27-beta.app/Contents/Developer xcodebuild test \
  -project kurl.xcodeproj -scheme kurl \
  -destination 'platform=iOS Simulator,id=<iPhone 17 Pro Max UDID>' \
  -only-testing:kurlUITests
```

- 시뮬레이터는 iPhone 17 Pro Max(iOS 27) 하나로만 검증했다.
- 스크린샷 자산은 결과 번들에서 뽑는다: `xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>`.
  첨부 `name` 이 파일명 힌트가 된다(`add(XCTAttachment)` 의 `lifetime = .keepAlways`).

## 검증 진입로(DEBUG 런치 인자)

| 인자 | 효과 |
| --- | --- |
| `--mocks` | 목 백엔드 + 자동 로그인(honggildong, me.id=1) |
| `--tab write --open compose --focus editor` | 새 글 컴포즈를 열고 본문 캔버스에 포커스(스니펫 바 등장) |
| `--post honggildong/hexagonal-after-3-months` | 하이라이트 시드가 칠해진 글로 바로 진입 |
| `--tab discover` | 발견 피드(하이라이트 카드 딥링크용) |
| `--force-coach` | 하이라이트 탭 코치 배너 강제 |

새 컴포즈는 항상 **빈 글**로 열린다. 미리 채워진 본문을 보려면 스튜디오 목록에서 기존 목 글
(초안 9001 / 발행 9002)을 눌러 연다.

## 매트릭스 — 글쓰기

판정: **커버(기존)** 원래 있던 테스트 · **커버(신규)** 이 PR 에서 추가 · **수동** 시뮬 자동화 부적합 · **갭** 자동화 가능하나 미작성(백로그)

| 기능 | 커버 테스트 | 판정 |
| --- | --- | --- |
| 컴포즈 진입(FAB·디버그) | 모든 컴포즈 테스트의 `launchFocusedEditor` | 커버(기존) |
| 본문 마크다운 에디터(입력·라이브 렌더) | `ComposeMarkdownRenderUITests.testMarkdownRendersWhileTyping` | 커버(기존) |
| 제목 입력 | `ComposePublishFlowUITests.launchComposeReady` | 커버(신규) |
| 굵게(감싸기·토글) | `ComposeSnippetBarUITests.testSnippetBarInsertsMarkdown` · `testEmphasisToggleOff` | 커버(기존) |
| 기울임(단일 별표) | `ComposeToolbarCoverageUITests.testItalicWrapsSingleAsterisk` | 커버(신규) |
| 제목 헤딩 순환(H1→H2→H3→본문) | `ComposeSnippetBarUITests.testSnippetBarInsertsMarkdown` | 커버(기존) |
| 목록·번호 줄머리(토글·교체) | `ComposeSnippetBarUITests.testLinePrefixToggleAndSwap` | 커버(기존) |
| 인용 줄머리 | `ComposeSnippetBarUITests.testLinePrefixToggleAndSwap` | 커버(기존) |
| 취소선(감싸기·토글) | `ComposeSnippetBarUITests.testEmphasisToggleOff` | 커버(기존) |
| 인라인 코드(백틱) | `ComposeToolbarCoverageUITests.testInlineCodeWrapsBacktick` | 커버(신규) |
| 코드 블록(진입·탈출) | `ComposeMarkdownRenderUITests.testMarkdownRendersWhileTyping` | 커버(기존) |
| 표 삽입(빈 줄 격리) | `ComposeSnippetBarUITests.testTableIsolatedByBlankLines` | 커버(기존) |
| 표 행/열 편집 + 삭제 되돌리기 토스트 | `ComposeToolbarCoverageUITests.testTableRowAddThenDeleteToast` | 커버(신규) |
| 리스트 Enter 연속·종료·번호 자동증가 | `ComposeSnippetBarUITests.testReturnContinuesList` | 커버(기존) |
| 리스트 들여쓰기·내어쓰기 | `ComposeToolbarCoverageUITests.testListIndentOutdent` | 커버(신규) |
| 실행취소·다시실행(+비활성 상태) | `ComposeToolbarCoverageUITests.testUndoRedoRestoresLastEdit` | 커버(신규) |
| 링크 다이얼로그(→https 정규화, `(url)` 리터럴 없음) | `ComposeMarkdownRenderUITests.testMarkdownRendersWhileTyping` | 커버(기존) |
| 동영상 다이얼로그(임베드 삽입) | `ComposeToolbarCoverageUITests.testVideoDialogInsertsEmbedURL` | 커버(신규) |
| 단일 URL 붙여넣기 → kurl 단축 치환 | `ComposeMarkdownRenderUITests.testPasteUrlBecomesKurlShortLink` | 커버(기존) |
| 클립보드 이미지 붙여넣기(#94) | `ComposeImagePasteUITests.testPasteClipboardImageInsertsMarkdown` | 커버(신규) |
| 이미지 편집 바 폭(기본·와이드·하프) | `ComposeImagePasteUITests.testImageActionBarWidthAndCaption` | 커버(신규) |
| 이미지 캡션 시트 | `ComposeImagePasteUITests.testImageActionBarWidthAndCaption` | 커버(신규) |
| 발행 시트 진입 | `ComposePublishFlowUITests.openPublishSheet` | 커버(신규) |
| 대표 태그 규칙(1개 필수·차단 사유) | `ComposePublishFlowUITests.testPublishRequiresTagThenCelebrates` | 커버(신규) |
| 태그 중복 제거·칩 삭제 | `ComposePublishFlowUITests.testTagFieldDeduplicatesAndDeletes` | 커버(신규) |
| 태그 대표 승격 | `ComposePublishFlowUITests.testTagPromoteToPrimary` | 커버(신규) |
| 발행 실행 → 성공 모먼트(`viewPublishedPost`) | `ComposePublishFlowUITests.testPublishRequiresTagThenCelebrates` | 커버(신규) |
| 사진 라이브러리 피커 첨부 | — | 수동 |
| 커버 이미지 지정(발행 시트) | — | 수동 |
| 자동저장 실패 토스트 | — | 수동 |
| 이미지 삭제 + 되돌리기 | 편집 바 버튼 존재만 확인(삭제 토스트 회귀는 표로 대표 검증) | 갭 |
| 자동저장 디바운스·저장 상태 아이콘 | — | 갭 |
| 소개글(excerpt) 입력 | — | 갭 |
| 시리즈 선택·새 시리즈 만들기 | — | 갭 |
| 예약 발행(프리셋·DatePicker) | — | 갭 |
| 발행 후 수정(글 정보·다시 게시) | — | 갭 |
| 리비전 시트·복원 | — | 갭 |

## 매트릭스 — 하이라이트

| 기능 | 커버 테스트 | 판정 |
| --- | --- | --- |
| 롱프레스 문장 스냅 → 하이라이트 | `HighlightReaderUITests.testLongPressSnapsToSentence` | 커버(기존) |
| 더블탭 선택 → 하이라이트 | `HighlightReaderUITests.testReaderHighlightFlow` | 커버(기존) |
| 하이라이트 칠 렌더(로드 시) | `HighlightReaderUITests.*` | 커버(기존) |
| 하이라이트 탭 → 답글 스레드 시트 | `HighlightReaderUITests.testReaderHighlightFlow` | 커버(기존) |
| 답글 작성 왕복(스레드에 반영) | `HighlightNoteReplyUITests.testReplyPersistsInThread` | 커버(신규) |
| 내 답글 삭제(소유 검사) | `HighlightNoteReplyUITests.testDeleteOwnReply` | 커버(신규) |
| 메모와 함께 하이라이트('메모' 액션·시트) | `HighlightNoteReplyUITests.testCreateHighlightWithNote` | 커버(신규) |
| 스레드 → 컬렉션 연결(`connectHighlightButton`) | `HighlightReaderUITests.testConnectHighlightFromThread` | 커버(기존) |
| 스레드 "이 문장이 속한 길" | `CollectionPathUITests.testThreadShowsContainingPaths` | 커버(기존) |
| 발견 하이라이트 카드 딥링크 | `HighlightReaderUITests.testDiscoverHighlightDeepLink` | 커버(기존) |
| 탭 코치 배너 | `HighlightReaderUITests.testHighlightTapCoach` | 커버(기존) |
| 내 하이라이트 목록(그룹·검색) | `SignedInScreensUITests.testMyHighlights` · `testMyHighlightsGroupAndSearch` | 커버(기존) |
| 다크 틴트(#96) | `highlight-dark-tint.png`(simctl appearance dark) | 수동 |
| 내 하이라이트 빈 상태 | — | 갭 |
| 하이라이트 자체 해제·삭제(리더) | 리더 UI 에 미연결 — 아래 '관찰' 참고 | N/A |

## 신규 테스트(14개)

- **ComposeToolbarCoverageUITests** (6): `testItalicWrapsSingleAsterisk`, `testInlineCodeWrapsBacktick`,
  `testUndoRedoRestoresLastEdit`, `testVideoDialogInsertsEmbedURL`, `testListIndentOutdent`,
  `testTableRowAddThenDeleteToast`
- **ComposePublishFlowUITests** (3): `testPublishRequiresTagThenCelebrates`,
  `testTagFieldDeduplicatesAndDeletes`, `testTagPromoteToPrimary`
- **ComposeImagePasteUITests** (2): `testPasteClipboardImageInsertsMarkdown`(#94),
  `testImageActionBarWidthAndCaption`
- **HighlightNoteReplyUITests** (3): `testReplyPersistsInThread`, `testDeleteOwnReply`,
  `testCreateHighlightWithNote`

## 수동 확인 항목(자동화하지 않은 이유)

- **사진 라이브러리 피커·커버 이미지** — PHPicker 는 프로세스 밖 시스템 시트라 앱 식별자가 없고
  실기기/시뮬 간 좌표가 흔들려 불안정. 이미지 삽입은 클립보드 붙여넣기(#94)로 대신 커버한다.
- **자동저장 실패 토스트** — 목 백엔드는 저장을 항상 성공시켜 실패 경로를 결정적으로 만들 수 없다.
  실패 주입 훅이 없으므로 수동(비행기 모드 등)으로 확인한다.
- **다크 틴트(#96)** — XCUITest 는 실행 중 외형(dark/light)을 바꿀 수 없다. `xcrun simctl ui <udid>
  appearance dark` 로 시뮬 외형을 바꾼 뒤 시드 글을 띄워 스크린샷으로 확인했다(라이트=accent-600
  0.18, 다크=accent-500 0.28 — 검은 본문에서도 물러나지 않게 중간 톤 accent-500 사용).

## 관찰(제품 기능 버그 아님)

1. **하이라이트 자체 해제/삭제가 리더 UI 에 미연결.** `HighlightsAPI.delete(id:)` 는 있으나 호출부가
   없다(리더·MyHighlights 컨텍스트 메뉴 모두 "컬렉션에 연결"만 제공, 삭제 없음). 답글은 지울 수
   있지만 하이라이트 자체는 못 지운다. 의도된 설계일 수 있어 버그로 보고하지 않고 관찰로 남긴다.
2. **접근성 식별자가 앱 전체에 2개뿐**(`viewPublishedPost`, `connectHighlightButton`). 나머지 글쓰기·
   하이라이트 컨트롤은 한국어 라벨/플레이스홀더로 찾는다. 레인은 ko 로케일에서 견고하지만, ko/en/ja/
   vi/hi 재번역이 라벨을 바꾸면 취약해진다. 발행 주버튼·본문 캔버스·태그 입력·답글 보내기/삭제·
   MyHighlights 행에 식별자를 붙이면 i18n 표류에 강해진다(동작 변경 없이 식별자만).
