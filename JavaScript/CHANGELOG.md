# 2.0.0
## Breaking Changes
- `MineStat#init` is now `MineStat#initSync` to maintain callback functionality
- A client timeout will not longer end the process

#### All Changes
- fix(timeout): Resolves issue where if used as library, a timeout would fire `process.exit()` ending the parent app
- chore(errors): Changes the callback signature to `(error: Error | never, result: Stats) => void`
- chore(types): Adds typescript definitions
- feat(promise): Move `init` to `initSync`. `init` now returns a promise
