# File-based coverage gate

Run from the repository root:

```sh
moon run cmd/check -- verify-plan fixtures/coverage/contract.json fixtures/coverage/plan.json fixtures/coverage/startup.record.json fixtures/coverage/traffic.record.json --json
```

This returns compatible and exit 0. Omit the traffic record and it returns
inconclusive, exit 3. The fixture definitions, records and source identifiers are
synthetic. No server or private infrastructure is needed.

Plan format 1 is an object with exactly `version: 1` and `requirements`, an object
mapping declared family names to arrays of required source identifiers. Names
refer to record `source` fields, not record filenames. There are 1–10,000 family
requirements and 1–64 distinct sources per family. Plans are bounded to 2,097,152
UTF-16 code units and JSON depth 32. Unknown fields, duplicate keys, blank source
names and duplicate sources are rejected. Unknown family names reject verification.

Prepare records with `record SCRAPE.om`, saving stdout to a UTF-8 file using your
normal build system. That command validates the supported wire profile first.
Record files contain only descriptor evidence; they omit original sample/label
values. Their source identifiers are caller assertions, not authenticated test
identities. The included source names are illustrative; create a plan using the
source identifiers emitted by your own records.

`verify-plan` accepts 1–64 records with unique source identifiers. Every observed
descriptor is checked against the declaration, including families without a plan
entry. The plan adds source-specific emission requirements; it does not filter
observations or suppress schema failures. Missing required sources/families are
unknown, while definite schema violations remain breaking. Aggregate evidence
and all diagnostics are retained. A successful gate covers only these supplied
records and requirements, not every possible runtime path.

The underlying portable APIs are `read_coverage_plan`, `read_observation` and
`verify_required_sources`; the latter can also receive requirements constructed
programmatically. The CLI supports Wasm and native, with exit codes 0 compatible,
1 incompatible, 2 invalid input and 3 inconclusive.
