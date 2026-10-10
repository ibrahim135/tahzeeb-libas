# Project instructions

- Read docs/PROJECT_SPEC.md and docs/IMPLEMENTATION_PLAN.md before implementation. Work only on the phase the user requests; do not start Phase 1 without instruction.
- Build an offline Android-first Flutter app with Material 3, Riverpod and Drift SQLite in persistent application storage. No backend, cloud sync, inventory or cloth/material calculation.
- Use the existing isolated checkout. Do not create a Git worktree unless explicitly requested.
- Keep UI, application logic, repositories, persistence, XLSX transfer and PDF generation separate. Select compatible packages using the actual installed stable Flutter/Dart SDK; commit the resolved application lockfile.
- Use UUIDs internally, distinct unique visible bill numbers, text phone numbers, integer paise and exact optional decimal measurements. Preserve garment terminology and item-owned historical measurement snapshots.
- Derive payment status from active payment sums. Validate financial changes transactionally; prevent overpayments and totals below received. Keep delivery status independent.
- Use explicit tested migrations, foreign keys and transactions for multi-table writes. Imports are versioned, previewed, idempotent and atomic; never silently overwrite or evaluate Excel formulas.
- No secrets or sensitive customer details in Git/logs. Use Android system file integrations without broad storage permissions. Warehouse PDFs exclude money.
- Preserve working functionality and user changes. Write working code and meaningful phase tests. Run flutter analyze, flutter test and applicable builds; distinguish device checks, skips and blockers from passes.
- Report changed files, executed validation, remaining issues and next steps. Do not claim production readiness without durable-data, Android lifecycle and release validation.
