# ExporterContract

[![checks](https://github.com/cn-nnzy/ExporterContract/actions/workflows/ci.yml/badge.svg)](https://github.com/cn-nnzy/ExporterContract/actions/workflows/ci.yml)

Catch exporter schema changes before a release breaks dashboards and alerts.
A portable MoonBit library and file-based CI tool for reviewed metric contracts,
observed-export conformance, test-source coverage and explicit migration decisions.

**Initial usable version: 0.1.0**, available from this repository under Apache-2.0.
Not published to Mooncakes. Examples need no Prometheus server or private service.

## Try it

Install [stable MoonBit](https://www.moonbitlang.com/download/), then run:

```sh
git clone https://github.com/cn-nnzy/ExporterContract.git
cd ExporterContract
moon update
moon run cmd/check -- verify fixtures/kubernetes/baseline.json fixtures/kubernetes/observation.om --json
moon run tools/e2e.mbtx
```

The first check returns compatible. The Kubernetes fixture uses three real
upstream metric definitions with synthetic observations and candidate mutations,
not a live cluster capture. See [fixture provenance](fixtures/kubernetes/README.md).

```sh
moon run cmd/check -- compare fixtures/kubernetes/baseline.json fixtures/kubernetes/breaking.json --json
```

This deliberately exits 1: a family was removed, a label was replaced and histogram
bounds changed. The strict stable-v1 policy freezes existing kind, explicit unit,
label names and finite classic histogram bounds, independently of consumer queries.

## Adopt the workflow

1. Use `draft EXPORTER SCRAPE...` to prepare an incomplete declaration.
2. Review scope and missing emitters before explicitly attesting completeness.
3. Keep the released baseline; run `compare` and integration-scrape verification.
4. Use descriptor-only records and a coverage plan for source-specific CI checks.
5. Record deliberate breaking migration decisions without changing the underlying
   incompatible verdict.

Missing observation is unknown, never proof of deletion. Good evidence cannot
overwrite bad evidence. Unsupported input rejects the whole input.

## Commands

Prefix each command with `moon run cmd/check --`. File inputs are local UTF-8.
Artifact commands print JSON; gate commands accept optional `--json`.

| Command | Purpose |
| --- | --- |
| `compare BASE CAND [--json]` | Declared compatibility gate |
| `verify CONTRACT SCRAPE [--json]` | Single-export conformance gate |
| `verify-many CONTRACT SCRAPE... [--json]` | Batch gate and emission coverage |
| `draft EXPORTER SCRAPE...` | Incomplete draft; conflicts reject |
| `record SCRAPE` | Validate scrape and emit descriptor-only evidence |
| `verify-record CONTRACT RECORD [--json]` | Replay descriptor evidence |
| `verify-plan CONTRACT PLAN RECORD... [--json]` | Require emission from designated sources |
| `normalize CONTRACT` | Validate and canonicalize declaration |
| `combine CONTRACT...` | Merge consistent declarations; reject contradictory completeness |
| `select CONTRACT SCOPE FAMILY...` | Explicitly named subset, inheriting completeness |
| `diff BASE CAND` | Exact before/after schema artifact |
| `review-template BASE CAND` | Exact-model-bound review template |
| `assess BASE CAND REVIEW [--json]` | Migration decision gate |

Gate exits: **0 compatible, 1 incompatible, 2 invalid, 3 inconclusive**.
Artifact commands return 0 for successful preparation, including breaking diffs;
they are not compatibility gates. Assessment exits are 0 ready, 1 needs review,
2 invalid/stale, 3 inconclusive. Errors are JSON on stderr; results are on stdout.

## Library and detailed examples

The root package `cn-nnzy/exportercontract` contains validated models, strict JSON
codecs, comparisons, composition, scope selection, coverage and migration review.
`adapters/openmetrics` reuses
[moonopenmetrics](https://mooncakes.io/docs/JYPeng487/moonopenmetrics) for parsing
and semantic validation. Public APIs are recorded in generated `pkg.generated.mbti`.

```sh
moon run examples/api
moon run examples/coverage
moon run cmd/check -- verify-plan fixtures/coverage/contract.json fixtures/coverage/plan.json fixtures/coverage/startup.record.json fixtures/coverage/traffic.record.json --json
```

The coverage library example deliberately asserts an inconclusive verdict:
startup evidence does not satisfy a traffic-test requirement. The file gate
uses synthetic records covering both required sources and returns compatible.

* [Contract format, policy and resource limits](docs/contract.md)
* [File-based coverage plan workflow](docs/coverage-plan.md)
* [Migration review example and trust model](docs/migration.md)
* [Ecosystem boundary](docs/ecosystem.md)
* [Third-party sources and licenses](THIRD_PARTY.md)
* [Initial version changes](CHANGELOG.md)
* [Development and verification](CONTRIBUTING.md)

Records omit raw sample/label values and original wire bytes. They are asserted
descriptor evidence, not authenticated scrape captures or proof of wire validity.
Source identifiers and review identities are caller assertions. Unknown fields,
profiles, duplicate keys and unsupported data are rejected.

## Supported scope

The pure library and adapter support Wasm, Wasm-GC, JavaScript and native.
The file CLI supports **Wasm and native**. CI builds/tests all four targets on
Linux, macOS and Windows and executes CLI scenarios on Wasm and native.
JavaScript requires Node.js; Windows native needs a Visual C++ developer environment.

Wire support is the documented OpenMetrics 1.0 profile: explicit counter, gauge
and classic histogram families with EOF. Summaries, info/state sets, native
histograms, exemplars, explicit timestamps and created-time series are rejected.
HTTP collection, time-series storage, PromQL parsing, alert graphs, sample-value
comparison and arbitrary policies are outside this version.

Development validation uses moon 0.1.20261104 and moonc v0.10.20+65efd5b93.
CI installs stable and records the actual version. Run
`moon run tools/validate.mbtx` for local portable checks; CI additionally verifies
native execution. The initial milestone is complete at this boundary. Additional
wire profiles and distribution packages remain future work. No production
adoption, ecosystem uniqueness or performance superiority is claimed.
