# Rescued foreign work — shared refs/stash collision (UI-PARITY agent, 2026-07-18)

While the UI-PARITY agent (branch loop/ui-parity-chat-voice) ran `git stash`
to base-check a test on a fresh worktree, a CONCURRENT agent's `git stash pop`
grabbed the wrong entry off the repo-global `refs/stash` stack. Net effect:
- The UI-PARITY agent's 4 files got popped into the MAIN checkout
  (loop/playground-ai-news) working tree (since removed — they are safely
  committed as 9c64119 on loop/ui-parity-chat-voice).
- Other agents' UNCOMMITTED work got dumped into the ui-parity worktree, then
  backed up here before that worktree was cleaned.

## What's in this backup (a MIX of ≥2 agents' work — DO NOT blind-apply)
- `foreign_tracked.patch` — `git diff` vs base 00fd91b of these tracked files:
  app_router.dart, app_shell.dart, downloads/{background_downloader_backend,
  download_backend, download_manager, download_notifications}.dart,
  chat/widgets/empty_states.dart, models_hub/ui/model_detail_screen.dart,
  test/data/downloads/download_notifications_test.dart,
  test/features/chat/widgets/empty_states_test.dart
- `foreign_untracked.tgz` — new files: features/playground/** (+ its test),
  models_hub/widgets/quant_quality.dart (+ test),
  test/data/downloads/download_progress_eta_test.dart
- `foreign_untracked_list.txt` — the untracked file list.

## Likely ownership (by file domain)
- downloads/* + quant_quality + download_progress_eta  -> loop/ux-benchmark-eta-value
  (that worktree at .claude/worktrees/ux-benchmark STILL has a partial copy of
   its downloads changes — reconcile, don't duplicate)
- features/playground/** + ai_news + app_router/app_shell playground routes
  -> loop/playground-ai-news (main checkout — its tree was emptied by the race)

## Recovery
Orchestrator should split this by owner and re-apply per branch, or have each
agent re-run its loop. The patch is vs 00fd91b; apply with `git apply
--3way`/`--reject` from a 00fd91b base and hand-resolve.
