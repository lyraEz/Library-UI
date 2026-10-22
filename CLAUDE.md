# Repository conventions

- Commits are authored as the repository owner (LyraEz). Do not add `Co-Authored-By` trailers, "Generated with" notices, session links or other AI attribution to commits, pull requests, code comments or documentation.
- Write concise commit messages that describe the actual change, in the existing style of `git log`.
- `src/Lyra.lua` is the published library. Run `tests/run.sh <luau>` before pushing a change to it, and keep `site/docs.html` in step with its public API.
- The website in `site/` has no build step. Keep it plain HTML, CSS and JavaScript.
