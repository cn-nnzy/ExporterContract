# Contract format and checking rules

## Declaration

```json
{
  "version": 1,
  "exporter": "my-service",
  "complete": true,
  "metrics": [
    {"name": "requests", "kind": "counter", "unit": null, "labels": ["method", "status"]},
    {"name": "duration_seconds", "kind": "histogram", "unit": "seconds", "labels": [], "buckets": [0.1, 0.5, 1]}
  ]
}
```

Names are OpenMetrics **family** names. A counter named `requests` emits
`requests_total`; the contract declares `requests`. Histogram `buckets` contain
finite bounds, with `+Inf` implicit. Bounds must be strictly increasing, and
there must be at least one finite bound. Numeric bounds use binary64 comparison;
the format does not preserve a number's spelling or arbitrary decimal precision.
Units are explicit metadata; they are not inferred from name suffixes.

All top-level fields and all descriptor fields except `buckets` are required.
`unit` must be null or a valid identifier. Non-histogram buckets may be omitted
or empty. Unknown fields, duplicate JSON keys (including escaped aliases),
unsupported versions/kinds and malformed values reject the entire declaration.
There is no forward-field passthrough. This format describes schemas, not a
lossless representation of arbitrary JSON or OpenMetrics text.

`complete` is a statement made by the declaration's author, not something inferred
from a scrape. It covers the exporter identifier's declared scope. If only a
subset is reviewed, use a distinct scoped exporter identifier consistently and
filter input outside this checker, or mark an exporter-wide inventory incomplete.
Never mark a partial exporter-wide scrape as an exhaustive declaration.

Canonical output sorts family and label names lexicographically and uses fixed
object field order, two-space indentation and a final newline. Input array order
does not affect comparison. Constructors and getters copy arrays to keep a
validated model from being mutated through caller-owned data.

## Policy and evidence

Under `stable-v1`, changing an existing kind, explicit unit, label-name set or
classic histogram layout is breaking. A renamed label produces removal and
addition findings; there is no heuristic rename matching. A newly declared
family produces a notice. A family absent from a complete candidate is removed;
absence from an incomplete candidate is unknown. Comparing different exporter
identifiers is an input error. Any incomplete declaration makes the comparison
inconclusive unless a definite breaking finding already determines the verdict.

Observation checking compares **every** label-value group separately. A
conforming group cannot hide another group with a missing label or different
histogram layout. A family absent from an observation is unknown. An observed
but undeclared family is breaking against a complete contract and unknown against
an incomplete one. Missing HELP text is allowed because prose is not contracted.
Other parser/validator violations reject input before any contract verdict.

Finding severity is `notice`, `unknown` or `breaking`. Breaking findings dominate
unknown findings; unknown dominates notices. Reports are ordered by metric name,
code, then location. JSON report version 1 contains `policy`, `scope`, `verdict`
and `findings`; each finding has severity, code, metric, location, message and
remedy. Observation locations are source identifiers and descriptor indices,
not source spans. Parser errors include line/column when available.

## Accepted observation profile

The adapter accepts OpenMetrics 1.0 text with its required EOF marker and
explicit counter, gauge and classic histogram types. Existing parser and
validator behavior comes from `JYPeng487/moonopenmetrics@0.1.1`.

Explicit timestamps, exemplars, `_created` series, summaries, info, state sets,
gauge histograms, unknown types and native histograms are unsupported. They are
rejected rather than silently projected into an apparently compatible result.
Label names `le`, `quantile` and `__*` are reserved in declarations. Histogram
`le` is interpreted only as the bucket-bound dimension. Label values and sample
values are used for structural validation, not retained in the public model or
report. This tool does not compare sample magnitudes, cardinality, metric help
text, alert behavior or PromQL semantics.

## Limits and errors

| Boundary | Limit |
| --- | --- |
| JSON or OpenMetrics source string | 2,097,152 UTF-16 code units |
| CLI file | 8 MiB, strict UTF-8; leading UTF-8 BOM accepted |
| JSON nesting | 32 |
| Metric/label/unit names | ASCII identifiers, at most 256 code units |
| Exporter / observation source identifier | 256 / 1,024 code units, nonblank |
| Declared / parsed families | 10,000 |
| Labels / finite bounds per descriptor | 64 / 256 |
| Parsed samples per family / scrape | 4,096 / 20,000 |
| Manually constructed observed descriptors | 100,000 |

Limits are application limits, not claims about the full OpenMetrics standard.
Parsing the bounded text occurs before counting parsed families/samples. Root
errors are `ContractError(code, path, message)`; adapter errors are
`ExportError(code, location, message)`. No mutable global state or partial result
is retained after failure. Corrected input can immediately be processed again.
The CLI returns structured diagnostics and exit 2 for invalid or unsupported
input. Invalid command syntax prints usage and exits 2.

## Three practical workflows

* **Exporter release review:** a maintainer keeps the released exhaustive
  declaration, edits the next version with instrumentation changes, and compares
  them in CI. A changed label or bound identifies a migration decision before
  deployment.
* **Integration-test conformance:** a platform team invokes exporter paths and
  saves their OpenMetrics output. Verification checks every observed descriptor
  against the reviewed declaration. An unobserved lazy metric returns unknown
  and asks for the path that emits it.
* **Downstream library gate:** a MoonBit application constructs declarations and
  observations programmatically, uses `Report::verdict()` to gate its own release
  process, and stores `Report::to_json()` as a review artifact. It needs no CLI,
  network service or Prometheus installation.
