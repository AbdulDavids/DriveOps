# DriveOps docs

Working notes on how the app is built and why, kept up to date as the code changes. Start here:

- [Architecture overview](architecture/overview.md) — project structure, tab layout, the connection types
- [Connection lifecycle](architecture/connection-lifecycle.md) — how connect/disconnect/poll actually work
- [Data flow](architecture/data-flow.md) — where state lives and how it reaches the UI
- [Decisions](decisions.md) — why things are built the way they are, including rejected alternatives

For the OBD2 library itself (what it is, why we forked it, known bugs), see the [README](../README.md#how-it-works) and `swiftobd2-bug-report.md` at the repo root.
