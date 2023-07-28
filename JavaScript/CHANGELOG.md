# 2.0.0
- fix(timeout): Resolves issue where if used as library, a timeout would fire `process.exit()` ending the parent app
- chore(errors): Changes the callback signature to `(error: Error | never, result: Stats) => void`
- chore(types): Adds typescript definitions
