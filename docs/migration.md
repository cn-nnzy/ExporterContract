# Reviewing a breaking migration

A deliberately accepted schema change remains a breaking change. This workflow
records a decision for a particular pair of declarations without changing the
compatibility report or approving missing evidence.

## Run the example

```sh
moon run cmd/check -- review-template fixtures/migration/baseline.json fixtures/migration/candidate.json
moon run cmd/check -- assess fixtures/migration/baseline.json fixtures/migration/candidate.json fixtures/migration/pending.json --json
moon run cmd/check -- assess fixtures/migration/baseline.json fixtures/migration/candidate.json fixtures/migration/approved.json --json
```

The template command prints a JSON artifact. The pending assessment exits 1 with
`review_status: "needs-review"`. The approved assessment exits 0 with
`review_status: "ready"`, while `compatibility.verdict` is still `incompatible`.
All migration fixtures, reviewer names, decisions and ticket references are
project-authored **synthetic examples**, not real approval records.

For a real release, save the generated template as a review file, retain its
embedded baseline and candidate models, and review every breaking entry. Fill
in `reviewer`, `reason` and `reference` for decisions already made through your
normal review process. Remove unapproved entries to assess a partial review.
Blank placeholders are invalid; they are never interpreted as consent. Commit
the record alongside the candidate and assess all three files in release CI.

## Exact binding

Review format 1 has exactly these top-level fields:

* `version`: 1.
* `policy`: `stable-v1`.
* `baseline` and `candidate`: entire contract-format-1 objects.
* `approvals`: individual decisions containing `code`, `metric`, `location`,
  `reviewer`, `reason` and `reference`.

The first three decision fields must identify an actual breaking finding for
the bound contracts. There are no wildcard approvals. Duplicates, unknown fields,
duplicate JSON keys (including escaped aliases), approvals of notices/unknowns,
and empty or control-containing review metadata reject the whole record.
Reviewer, reason and reference are each limited to 1,024 UTF-16 code units;
there are at most 10,000 decisions. Review input is limited to 2,097,152 code
units and JSON nesting depth 32. Oversized generated templates are also refused.

`assess_migration` compares both validated models to the embedded declarations.
Any semantic model change, including an additive metric, explicit unit, exporter
scope or completeness flag, makes the review stale. Family/label ordering,
JSON whitespace and numeric spelling do not invalidate semantically equal
models. This binding uses canonical models rather than a claimed cryptographic
signature. A file's reviewer field is a recorded assertion: it does **not**
authenticate a person. Use repository review/access controls for authorization.

## Status and exit codes

| Review status | Exit | Meaning |
| --- | --- | --- |
| `ready` | 0 | Every breaking finding has a recorded decision and no unknown evidence remains |
| `needs-review` | 1 | At least one breaking finding remains outstanding |
| invalid input | 2 | Malformed, unsupported or stale record; no assessment returned |
| `inconclusive` | 3 | No unapproved breaking findings remain, but unknown evidence remains |

If both outstanding breaking findings and unknown evidence exist, the status is
`needs-review`; the unchanged compatibility report retains both. After all
breaking findings are approved, incomplete declarations still produce
`inconclusive`. For example:

```sh
moon run cmd/check -- assess fixtures/migration/baseline.json fixtures/migration/partial.json fixtures/migration/incomplete.json --json
```

The report JSON keeps the original comparison under `compatibility`, lists
recorded `approvals`, and lists the exact IDs of `outstanding` breaking findings.
This is migration process readiness, not runtime coverage or a claim of backward
compatibility. Observation verification and the original `compare` command are
unaffected.

The portable library exposes `migration_template`, `read_migration_review` and
`assess_migration`; inspect the generated interface for record accessors.
Review JSON can be round-tripped with `MigrationReview::to_json()` and decisions
are sorted deterministically. No external service or credential is needed to
exercise this example.
