# omarchy-notification-center -- Todo

## Notes & Conventions
- This repo is public: nothing personal in `claude/` (no usernames, home paths with names,
  hardware models, accounts, or the maintainer's other repos and configs).
- Develop here; load into the installed plugin by fast-forwarding its clone and restarting
  the shell (workstream "Where things live").
- A shortcut is added in one place, `Shortcuts.js`; the footer hint and the key handler both
  read that table.
- Before calling a change done: `tests/run.sh`, then `tests/e2e/smoke.py <dir>` and look at
  its screenshots against the checklist in `docs/TESTING.md`. New logic gets a test that
  fails on a broken copy (mutation check), not just one that passes.

## Open
- [ ] `notification-panel`: 82d8032 loaded (bug-finder fixes, not pushed); next = visual
  check (NEW highlight, expand/collapse, undo line), push, maybe a 2.0.0
  CHANGELOG/manifest bump. Live action buttons PARKED
  (minimal Service.qml patch vs upstream API request)
  -> `claude/workstreams/notification-panel.md`
