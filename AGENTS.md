# datetime-utils (Zap package) — contributor & agent conventions

This is an official **non-core** Zap package: dateutil-style datetime utilities. These conventions apply to everyone working in this repo, human or agent.

## Project scope & design

- **Python-parity rule.** The public API mirrors [python-dateutil](https://dateutil.readthedocs.io/) (`parser`, `relativedelta`, `rrule`, `tz`, `easter`, `utils`) as closely as Zap's static typing allows.
- When a shape cannot match dateutil cleanly — keyword-argument ergonomics, Zap's requirement of a single declared return type, a word Zap reserves, bytes-vs-str — **do not guess.** Record the chosen deviation and its rationale in `DECISIONS.md`, keyed to the issue, citing the dateutil reference it follows or departs from.
- **Builds on core Zap `datetime` + the core tz database.** Do not reimplement IANA tz data or core datetime arithmetic — wrap/alias the core capability to the dateutil name. Record each alias decision in `DECISIONS.md`.

## Issues & PRs

- Keep issues concrete and testable, with as much detail as possible: the target dateutil API, the behavior involved, and explicit acceptance criteria.
- Multi-issue features get an **Epic** with linked, trackable sub-issues.
- Individual issues should be **'M'-sized**. Don't split an epic into unnecessary 'S'-sized issues.
- **One issue → one PR.** Branch fresh from `origin/main`; **rebase onto `origin/main`** before opening a PR and before pushing follow-up commits.
- **All package issues live in this repo** (zaplang-io/datetime-utils), not in zaplang-io/zap.
- Conventional-commits PR titles.

## Core-language defects (important)

This package is built on the Zap language, core `datetime`, and the tz database. If package work exposes a **core language or stdlib defect**:

- **Report it in `zaplang-io/zap`**, and stop at reporting it.
- **Never work around a core defect** to make this package function. Keep the dependent work blocked/draft and note the dependency.
- Do not implement a core fix here; the Zap maintainer decides who fixes it and when.

## Decisions

- Record every non-obvious API/design decision in **`DECISIONS.md`**, keyed to its issue, citing the dateutil reference it follows or deviates from. Keep it current with every PR that changes the public surface.

## Documentation

- Keep `README.md` and `DECISIONS.md` up to date with every PR that changes behavior or the public API.
- User-exposed functions carry docstrings suitable for later documentation generation.

## Tests

- Tests are **exhaustive, not minimal** — intent documentation and a walled garden around calendar/time behavior. Cover: leap years, month-end clamping, DST transitions (fold/gap, ambiguous/imaginary times), 2-vs-4-digit years, far-past/future years, infinite rules bounded by count/until, and malformed input.
- When fixing a bug, **first add a failing test** that reproduces it, then fix.
- Do not assume dict/set iteration order in assertions (it is unspecified in Zap).

## Attribution

- Commits, PR descriptions, and issue/PR bodies carry **only the author's name** — no `Co-Authored-By`, no "Generated with …", no model mention anywhere. This follows the `zaplang-io` org convention. (Issue/PR **comments** may carry a review-attribution note such as "Reviewed by …" / "… input on …".)
