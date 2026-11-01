---
title: Daily assistant — brief
status: draft for owner review
date: 2026-11-01
---

# Brief: from "local chat app" to "private daily assistant"

## The ask (owner, 2026-11-01)

> "I want the app to be meaningful. A user can use it day to day. Without any marketing,
> without any branding, I got 100+ installs on the Play Store. I think this app has
> potential... It should solve users' problem. Add connectors to it so a user can locally
> add their Gmail to it, XYZ... Change the user interface also. I think the current user
> interface is very limited in scope... change the UI/UX experience also for the app
> end-to-end."

Locked by the owner on 2026-11-01:
- Connectors talk **only between the phone and the user's own provider**. No Dhruva server,
  no analytics. The model still runs 100% on the phone.
- Gmail connects with **Google sign-in (OAuth)**.
- First release connectors: **Email (Gmail), Calendar + Contacts, a Files/Notes folder,
  Android notifications digest**.
- Plus the four 0.7 features already in flight: **speed test + honest labels, chat with a
  document, battery & heat guard, Quick Settings tile + home widget**.
- iOS: keep 0.6.0 in Apple's queue; ship 0.7 to iOS after it is approved.
- Product name: to be decided later. All name strings live in one place so the rename is a
  one-line change.

## Why (the user's pain, in plain words)

Today the app is a private chat box with good tools hidden behind icons. The live audit
(`audit.md`) scored it **25/40** on Nielsen's heuristics. Walking a real day with a
daily-assistant user found that in 18 steps she has to **leave the app 7 times, guess 7
times, retype 5 times, and hits 6 things the app cannot do at all**. The app does not know
her day, her mail, her people or her files, so every useful task is a clipboard relay.

Competitors (PocketPal, Private LLM, Enclave, Edge Gallery, Layla — see `references.md`)
are almost all "pick a model, then chat". **None of them knows your day or your data
while staying fully on-device.** That is the open lane.

## What we are building

A private assistant you open every morning and use all day:

1. **Today** — the home screen. A short brief written on the phone from your calendar,
   important mail and the day's notifications, plus your next event, people you will meet,
   and one-tap actions. It is ready when you open the app, not after you type.
2. **Inbox** — your mail and notifications in one calm list, each with a one-line summary,
   "needs reply" first, and a drafted reply you edit and send yourself.
3. **Ask** — the chat, now able to look things up in your mail, calendar, contacts, files
   and documents, and show where every answer came from.
4. **Library** — your connected folder, attached documents, saved answers and to-dos.

Settings holds the plumbing: connectors (with a privacy ledger: what was read, when, and
"nothing left this phone"), models (download, speed test, compare), voice, appearance,
about.

## What does not change

- Everything still runs on the phone. No account, no cloud, no telemetry.
- Nothing is written or sent on the user's behalf without a tap. Read is the default.
- Every one of the 52 capabilities in the parity matrix (`audit.md` §6) survives the
  redesign, moved or renamed but not dropped.

## Honest limits (we design around these, not over them)

- On-phone models are small (0.5–3B). They are good at short summaries, rewrites,
  extraction and grounded answers. They are bad at long reasoning and multi-step agents.
  So: rules gather the data, the model writes short text, the human confirms every action.
- Gmail via Google sign-in needs Google's app verification before the public can use it
  (privacy policy on our domain, demo video, scope reasons; about 10 days). Until then it
  works for up to 100 test users who re-connect every 7 days. The paid security assessment
  (CASA) applies only to apps that keep mail on servers, so it should not apply to us
  (Google: "If you store or transmit restricted scope data on servers, then you need to
  complete a security assessment").
- iOS has no way for apps to read other apps' notifications; the digest is Android-only.
- Android 15 hides one-time-password notifications from apps like ours. Good.

## Success looks like

- A new user gets a useful Today brief in under 60 seconds (calendar needs no sign-in).
- The audit's day walk drops from 7 leave / 7 guess / 5 retype / 6 none to near zero.
- Heuristic score at least **34/40** on the re-audit (baseline 25).
- People open it on most days (Play "returning users", the only signal we have; no
  analytics by design).
