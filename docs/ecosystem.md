# Ecosystem boundary

This project owns reviewed exporter **schema contracts** and evidence-scoped
release verdicts. Its public operations are `read_contract`,
`compare_contracts`, `verify_export`, validated constructors and report output.
It does not own text parsing, instrumentation, query parsing or rule dependency
analysis. That boundary is intentional; the OpenMetrics adapter reuses an
existing parser instead of reproducing it.

Sources reviewed during project selection, 2026-11-08:

| Existing work | Relationship |
| --- | --- |
| [JYPeng487/moonopenmetrics](https://mooncakes.io/docs/JYPeng487/moonopenmetrics) | Reused parser/validator: `parse`, `validate`, metric-family/sample model. It validates an export; this project compares declarations across releases and scopes conclusions to observed evidence. |
| [moonbitstack/moonp8s](https://mooncakes.io/docs/moonbitstack/moonp8s) | Produces metric instrumentation/exporter output. Contract checking is downstream of instrumentation, with no registry or metric update API here. |
| [zhou-wei97/promql](https://github.com/zhou-wei97/promql) | Query/rule analysis is an adjacent area. This project deliberately excludes PromQL parsing, dependency graphs and alert impact analysis. |
| [Prometheus OpenMetrics specification](https://github.com/prometheus/OpenMetrics/blob/v1.0.0/specification/OpenMetrics.md) | Defines wire concepts used by the input adapter. Our accepted profile is narrower and rejects unsupported data. |
| [Kubernetes metrics stability](https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/) | A real use case for maintaining metric names/types/labels across releases; the fixture uses the upstream stable-metric inventory. |
| [prometheus/client_golang testutil](https://pkg.go.dev/github.com/prometheus/client_golang/prometheus/testutil) | Shows the practical demand for repeatable collection and exposition checks. ExporterContract adds explicit versioned declarations and incomplete-evidence verdicts for MoonBit consumers. |

Search vocabulary included `OpenMetrics`, `Prometheus`, `exporter`, `metrics`,
`contract`, `schema`, `compatibility`, `breaking`, `histogram`, `PromQL` and their
combinations across Mooncakes, GitHub and official documentation. Searches do
not establish ecosystem uniqueness: unpublished packages, unindexed repositories
and later releases may overlap. These links and the public API boundary support
a complementary scope, not an originality or exclusivity claim. Recheck the
boundary before expanding into another project's problem domain.
