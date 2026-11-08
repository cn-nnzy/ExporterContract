# Kubernetes descriptor fixture

`stable-metrics-list.yaml` is the unmodified upstream inventory from
[Kubernetes v1.35.0](https://github.com/kubernetes/kubernetes/blob/v1.35.0/test/instrumentation/testdata/stable-metrics-list.yaml),
Apache-2.0, copyright The Kubernetes Authors.

* Tag commit: `66452049f3d692768c39c797b21b793dce80314e`.
* Source path: `test/instrumentation/testdata/stable-metrics-list.yaml`.
* SHA-256: `ec10875b264af04dcc27d03842a0f2c93b5552d6ff3f96019156e912cf720677`.
* Retrieved: 2026-11-08.

`baseline.json` transcribes three STABLE families: `apiserver_request_total`,
`apiserver_request_duration_seconds`, and `apiserver_requested_deprecated_apis`.
The `apiserver` subsystem prefix is joined to each upstream name. The wire
counter suffix `_total` is removed to obtain its OpenMetrics family name.
Label names and histogram finite bounds come from the inventory. No explicit
UNIT metadata is present, so units are null rather than inferred from suffixes.

The exporter identifier `kubernetes-apiserver-reviewed-subset` and
`complete: true` describe **only this three-family fixture scope**. They are
not an assertion that a Kubernetes API server exports only these families.
Do not use this subset to check a full live `/metrics` endpoint.

`observation.om` has project-authored synthetic values and labels with the real
descriptor layouts. It is not a production scrape. Its histogram represents one
observation at 61 seconds. `breaking.json` intentionally changes the counter's
`code` label to `status_code`, removes the gauge, and removes the smallest
histogram bound. These are controlled test mutations, not a real Kubernetes
release change. `partial.json` deliberately contains no family declarations
and sets `complete: false`.

Run the documented checks in the root README or `moon run tools/e2e.mbtx`.
The end-to-end suite verifies return codes and machine-readable verdicts without
a cluster, exporter process or network access after dependency installation.
