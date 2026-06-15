# 절제 패스 심화 — audit & plan

The "왜 medium 앱은 깔끔하고 우리는 학생이 만든 앱 같지" diagnosis was: type scattered (raw
`font(.system(size:))` bypassing the `typeScale` tokens), green + glass over-used, density too high,
decoration winning over content. The first restraint pass proved the cure on the analytics screens
(selector pills → ink, `metaCount` → `metaLine`). This is the audit for taking it app-wide.

## Finding: typeScale is mostly already disciplined (good news)

An audit of every title-weight raw font (`size ≥ 16`, semibold/bold) across the app shows the
**majority are legitimate, not bypasses**:

- **Nav-bar principal titles** — `ToolbarItem(placement: .principal) { Text(...).font(.system(size: 16, weight: .semibold)) }` (TagFeedView, AuthorBlogView, PostDetailView). 16pt semibold is the standard inline nav title; it is *not* a `typeScale` role. Leave as-is.
- **Buttons / CTAs** — "시작하기" (ChooseUsernameView), EngagementDock counts. Control labels, not content titles. Leave.
- **Content titles already use tokens** — FeedRow / PostRow / Bookmark / Liked / MyHighlights / FollowLists titles are on `.typeScale(.title)` / `.titleSmall`. Good citizens.

**Genuine bypasses fixed:** `SubscribedSeriesView` series-row title was raw `16*unit semibold` while
its sibling library rows use `typeScale` → moved to `.typeScale(.titleSmall)` for consistency.

So type scatter is **largely solved**; chasing more typeScale conversions has low remaining ROI and
risks converting legitimate nav-titles/buttons (which would break them).

## The real residue (needs per-screen visual iteration, not bulk edits)

The remaining "학생 앱" feel is **colour / glass / density / decoration** — subjective per screen,
best done with the simulator open, one surface at a time. Concrete targets:

- **Green discipline** — green should mean *primary action* or *data*, nothing else
  ([[feedback_brand_color_green]] = #059669). Audit decorative green: eyebrow dots (`accentMarker`),
  list bullet markers, tag chips, "오늘의 글" link-colour eyebrow, pinned-pin accent. Keep green on the
  one primary action per screen + chart data; neutralise the rest to ink/secondary.
- **Glass discipline** — glass belongs on 1–2 floating chrome surfaces (nav/dock), per AGENTS §1.4
  "no glass-on-glass". Audit `glassEffect` / `glassCapsule` usages for decorative panels that should
  be flat (hairline) cards.
- **Density / whitespace** — the diagnosis flagged screens "욱여넣은" without breathing room (analytics
  was worst, partly addressed). Audit vertical rhythm: section spacing, card padding, line spacing.
- **Decoration** — marks/badges/dividers that compete with content; reduce to what carries meaning.

## How to execute (deliberately)

One screen at a time, simulator open (`--mocks`, see [[reference_kurl_ios_sim_verify]]):
screenshot → identify the one primary action (keep its green) → neutralise decorative green/glass →
add whitespace → re-screenshot → compare. This is a visual-judgment pass, not a find-and-replace, so
it should be its own focused session rather than a bulk diff. Honour AGENTS.md §10 "조용한 웹로그"
throughout; the user's taste is "living restraint" — rich motion within the quiet rules
([[user_polish_motion_taste]]), no decorative colour.
