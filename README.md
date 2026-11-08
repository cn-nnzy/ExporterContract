# ExporterContract

[![checks](https://github.com/cn-nnzy/ExporterContract/actions/workflows/ci.yml/badge.svg)](https://github.com/cn-nnzy/ExporterContract/actions/workflows/ci.yml)

Review an exporter's metric schema before a release reaches dashboards and alerts.
ExporterContract compares reviewed metric declarations and checks whether an
OpenMetrics scrape conforms to a declaration. It distinguishes a removed metric
from one that simply did not appear during a test.

The intended users are exporter maintainers and platform teams that need a
repeatable release check for metric names, types, label names, units, and classic
histogram buckets. The comparison engine is a MoonBit library; a file-based CLI
provides the same workflow for CI.

## Try it

Install the [stable MoonBit toolchain](https://www.moonbitlang.com/download/),
clone this repository, and run from its root:

```sh
moon update
moon run cmd/check -- compare fixtures/kubernetes/baseline.json fixtures/kubernetes/baseline.json
moon run cmd/check -- verify fixtures/kubernetes/baseline.json fixtures/kubernetes/observation.om --json
moon run tools/e2e.mbtx
```

Both checks return `compatible`. The end-to-end runner also checks failing and
inconclusive inputs, including these intentional changes:

```sh
moon run cmd/check -- compare fixtures/kubernetes/baseline.json fixtures/kubernetes/breaking.json --json
```

That command exits with **1**, reporting removal of a family, removal of the
`code` label, addition of `status_code`, and a changed histogram layout. The
fixtures use three real Kubernetes metric definitions; observed values and the
breaking candidate are deliberately synthetic. This is a reviewed subset, not
an exhaustive Kubernetes API server inventory. See
[fixture provenance](fixtures/kubernetes/README.md).

## Adopt the workflow

1. Describe the metric families your exporter promises to consumers. Commit the
   JSON contract with `complete: true` only when it exhaustively covers the
   exporter scope you are checking. Keep the baseline from the released version.
2. Update a candidate declaration alongside instrumentation changes. Run
   `compare baseline.json candidate.json --json` in release CI.
3. Exercise representative application paths, save their OpenMetrics output,
   and run `verify candidate.json scrape.om --json`. Missing observations require
   more evidence; they do not justify a deletion finding.

The `stable-v1` policy freezes each existing family's kind, explicit unit,
complete label-name set, and finite classic histogram bounds. Additions are
notices; deletion from an exhaustive candidate is breaking. This is a deliberately
strict release policy, not a claim that every schema change breaks every query.

| Exit | Meaning | Typical next action |
| --- | --- | --- |
| 0 | Compatible within the report's scope | Review notices, then accept this check |
| 1 | Incompatible | Preserve the schema or plan a consumer migration |
| 2 | Invalid or unsupported input / command | Correct the input; no partial verdict is returned |
| 3 | Inconclusive | Supply an exhaustive declaration or exercise missing emitters |

`compare` reports have scope `declared-contracts`. `verify` reports have scope
`observed-export-only`: even a successful scrape check cannot prove that unseen
runtime paths conform. Input failures go to stderr as JSON. Reports go to stdout
as text, or as versioned JSON with `--json`. `normalize CONTRACT.json` validates
and prints the canonical contract representation.

## Library API

For lazy metrics emitted by different integration paths, combine their evidence:

```sh
moon run cmd/check -- verify-many fixtures/coverage/contract.json fixtures/coverage/startup.om fixtures/coverage/traffic.om --json
```

The result includes sorted `sources` and per-family `coverage` entries. Every
descriptor is checked; a good scrape cannot override a mismatch in another.
Missing families are unknown only when absent from the entire batch. Sources
must be distinct, with 1–64 observations and at most 100,000 descriptors total.
The library operation is `verify_exports(contract, observations) -> BatchReport`;
`BatchReport::report()` returns the verdict/findings. This proves emission in the
supplied sources, not coverage of every runtime path. The synthetic fixtures in
`fixtures/coverage` model startup and traffic-driven emission.

The root package contains the model and policy, independent of file I/O. The
`adapters/openmetrics` package converts supported OpenMetrics observations using
[moonopenmetrics](https://mooncakes.io/docs/JYPeng487/moonopenmetrics).

```moonbit
let metric = @contract.Metric::new("requests", Counter, ["method", "status"])
let baseline = @contract.Contract::new("my-service", [metric], complete=true)
let candidate = @contract.read_contract(candidate_json)
let report = @contract.compare_contracts(baseline, candidate)
let observation = @openmetrics.read_export(scrape_text, source="integration-test")
let observed_report = @contract.verify_export(candidate, observation)
```

Import `cn-nnzy/exportercontract` as `contract` and
`cn-nnzy/exportercontract/adapters/openmetrics` as `openmetrics`. The snippet
belongs in a function handling `ContractError` and `ExportError`. The complete
[runnable library example](examples/api/main.mbt) constructs a declaration,
reads a scrape, checks it, and prints its report:

```sh
moon run examples/api
```

Version 0.1.0 is source-available here; it has not been published to Mooncakes.
Use this checkout for the commands above. Public API inventories are committed
as `pkg.generated.mbti` files. See [contract format and limits](docs/contract.md)
for the supported input profile and error rules.

## Support and validation

The pure library and OpenMetrics adapter support Wasm, Wasm-GC, JavaScript and
native targets. The asynchronous file CLI supports **Wasm and native**. It reads
local UTF-8 files and needs neither a running Prometheus server nor private
infrastructure. It does not fetch HTTP endpoints.

Development validation uses stable `moon 0.1.20261104` and
`moonc v0.10.20+65efd5b93`. CI installs the current stable distribution and prints
its version on Linux, macOS and Windows. Each job builds and tests all four
targets, checks generated interfaces, and executes the CLI on Wasm and native.
Windows native builds require a Visual C++ developer environment; the workflow
initializes it explicitly. JavaScript tests require Node.js.

```sh
moon fmt --check
moon info --target all
moon check --target all --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon build --target all --deny-warn
moon run tools/e2e.mbtx wasm
moon run tools/e2e.mbtx native
```

Tests cover strict input rejection and recovery, canonical round trips,
permutation invariance, defensive copies, bucket boundaries, incomplete
evidence, and supported observation profiles. Report data includes metric and
label **names**, but not observed label **values**. Callers choose source
identifiers, which are included in diagnostics.

## Next capabilities

The current milestone includes a file-based contract gate and multi-observation
coverage evidence. Follow-up work is ordered by workflow: prepare reviewable
declarations from observations, then add baseline migration support with explicit
approval records and narrowly reviewed metadata profiles. These are plans,
not implemented features. PromQL parsing, alert dependency graphs,
instrumentation and time-series storage remain outside the project boundary.

See [ecosystem boundary](docs/ecosystem.md) and
[third-party sources](THIRD_PARTY.md). Licensed under Apache-2.0.
