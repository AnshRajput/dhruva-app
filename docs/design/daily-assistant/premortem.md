---
title: Daily assistant — pre-mortem
date: 2026-11-01
---

# Pre-mortem: it is March 2027 and the daily-assistant release failed. Why?

| # | Failure story | Likelihood | Impact | Mitigation (owner of the fix) |
|---|---|---|---|---|
| 1 | **Summaries were bad.** 0.5–1B models wrote vague or wrong briefs; users stopped trusting Today. | High | High | Rules pick the facts; the model only phrases them; every sentence links to its source; facts list shown under the brief; recommend ≥1.5B when RAM allows; "brief quality" eval set of 20 fixture days run in CI on a small model before release. |
| 2 | **Gmail stuck in Google verification.** Public users saw "Google hasn't verified this app" or could not connect; testing tokens expired every 7 days. | High | Med | Ship calendar/contacts/folder/notifications first-class; Gmail labelled "Beta" with a clear reconnect banner; start verification immediately (needs domain + privacy policy + demo video); app fully useful without Gmail. |
| 3 | **Play rejected the update** for notification access or contacts. | Med | High | Notification listener is opt-in, explained in-app, core to the digest; fill Play's sensitive-permission declarations; contacts read minimal; ship digest behind a remote-free feature flag so it can be removed by a patch. |
| 4 | **Battery and heat complaints.** Background sync + indexing + summaries cooked phones. | Med | High | Index/summarize only while charging or on explicit refresh; WorkManager constraints; battery & heat guard (0.7 feature) gates generation; lazy summaries for visible rows only. |
| 5 | **Privacy backlash.** "Private offline AI now uses the internet." | Med | High | Network only to the user's own provider, shown live in the privacy ledger; store text and privacy policy updated in plain words; no new SDKs; Data safety: no data collected by developer. |
| 6 | **Migration lost chats.** Schema v5→v7 broke existing users' data. | Low | Critical | Additive migrations only; migration tests from real v5 fixtures; Shorebird can't fix native/migration mistakes, so test on a device with 0.6.1 data before release. |
| 7 | **Scope ate the schedule.** Four tabs + five connectors + four features never converged. | High | High | Phased build (below); each phase ships independently; the redesign shell lands first with existing features moved, connectors plug in one by one. |
| 8 | **Low-RAM phones crashed** while indexing PDFs or holding the model plus FTS. | Med | Med | Caps (file size, chars, items); extraction in isolates; skip indexing when free RAM low; speed test labels steer to smaller models. |
| 9 | **Existing users got lost.** Chat moved from tab 1 into Ask; Models disappeared into Settings. | Med | Med | First launch after update shows a 3-card "what moved" sheet; Ask keeps the same history; deep links (`/chat/:id`) still work. |
| 10 | **iOS felt half-done** (no notifications digest, different background behaviour). | Med | Low | Hide Android-only cards on iOS; never show a disabled feature; iOS ships after 0.6.0 approval anyway. |
| 11 | **Security hole in exported components** (tile/widget/listener/intent extras) let another app trigger actions or read data. | Low | High | Security-audit skill review on every PR (Rule 7); validate all intent extras; no exported component accepts data it trusts. |

## Assumptions the design rests on (and how we will know)
- People want a brief from on-device data more than better chat → watch Play returning-user stats + reviews after release.
- FTS5 keyword search is good enough for "find that email/file" → test on a real 2k-mail mailbox; parked fallback is embeddings.
- Users accept connecting calendar without an account → onboarding funnel visible only through reviews/feedback (no analytics by design).

## Phasing (each phase ships on its own)
1. **0.7a — shell + features:** new IA (Today/Inbox/Ask/Library, Settings), existing capabilities moved, D1–D16 fixes, the four in-flight features (speed test, doc chat, heat guard, tile/widget), About me, system theme.
2. **0.7b — device connectors:** calendar, contacts, folder, notifications digest, Today brief, privacy ledger.
3. **0.7c — Gmail (beta):** OAuth testing mode → verification → public.
