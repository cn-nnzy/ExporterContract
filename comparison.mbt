///|
fn finding(
  severity : Severity,
  code : String,
  metric : String,
  location : String,
  message : String,
  remedy : String,
) -> Finding {
  { severity, code, metric, location, message, remedy, }
}

///|
fn compare_metric(
  before : Metric,
  after : Metric,
  location : String,
  findings : Array[Finding],
) -> Unit {
  if before.kind != after.kind {
    findings.push(
      finding(
        Breaking,
        "kind-changed",
        before.name,
        location,
        "metric kind changed from \{kind_name(before.kind)} to \{kind_name(after.kind)}",
        "publish a new family name or keep the previous kind",
      ),
    )
  }
  if before.unit != after.unit {
    findings.push(
      finding(
        Breaking,
        "unit-changed",
        before.name,
        location,
        "declared unit changed",
        "keep the existing unit or introduce a separately named metric",
      ),
    )
  }
  for label in before.labels {
    if !after.labels.contains(label) {
      findings.push(
        finding(
          Breaking,
          "label-removed",
          before.name,
          location + "/labels/" + label,
          "declared label removed",
          "retain the stable label until consumers migrate",
        ),
      )
    }
  }
  for label in after.labels {
    if !before.labels.contains(label) {
      findings.push(
        finding(
          Breaking,
          "label-added",
          before.name,
          location + "/labels/" + label,
          "declared label added under stable-v1",
          "introduce a new metric family for the new label schema",
        ),
      )
    }
  }
  if before.kind == Histogram &&
    after.kind == Histogram &&
    before.buckets != after.buckets {
    findings.push(
      finding(
        Breaking,
        "buckets-changed",
        before.name,
        location + "/buckets",
        "finite classic histogram bucket layout changed under stable-v1",
        "keep the layout or review a separately versioned metric rollout",
      ),
    )
  }
}

///|
/// Compare declared inventories under stable-v1. This policy freezes existing
/// family kind, unit, label names, and classic histogram bounds.
pub fn compare_contracts(
  before : Contract,
  after : Contract,
) -> Report raise ContractError {
  if before.exporter != after.exporter {
    refuse(
      "exporter-mismatch", "/exporter", "compare contracts for the same exporter identifier",
    )
  }
  let findings : Array[Finding] = []
  let old : Map[String, Metric] = Map([])
  let current : Map[String, Metric] = Map([])
  for m in before.metrics {
    old[m.name] = m
  }
  for m in after.metrics {
    current[m.name] = m
  }
  if !before.complete || !after.complete {
    findings.push(
      finding(
        Unknown,
        "inventory-incomplete",
        "",
        "/complete",
        "at least one contract inventory is explicitly incomplete",
        "supply reviewed exhaustive contracts before accepting a full compatibility verdict",
      ),
    )
  }
  for metric in before.metrics {
    match current.get(metric.name) {
      Some(candidate) =>
        compare_metric(metric, candidate, "/metrics/" + metric.name, findings)
      None =>
        findings.push(
          if after.complete {
            finding(
              Breaking,
              "metric-removed",
              metric.name,
              "/metrics/" + metric.name,
              "family is missing from the complete candidate contract",
              "retain or explicitly migrate the previously declared family",
            )
          } else {
            finding(
              Unknown,
              "presence-unproven",
              metric.name,
              "/metrics/" + metric.name,
              "family is absent from an incomplete candidate inventory",
              "provide an exhaustive candidate inventory; absence here is not deletion evidence",
            )
          },
        )
    }
  }
  for metric in after.metrics {
    if !old.contains(metric.name) {
      findings.push(
        finding(
          Notice,
          "metric-added",
          metric.name,
          "/metrics/" + metric.name,
          "family is newly declared in the supplied candidate",
          "review its name and schema before making a stability commitment",
        ),
      )
    }
  }
  report("declared-contracts", findings)
}

///|
/// Verify only the descriptors present in this observation. A missing family
/// is inconclusive, never a deletion finding. Label values are not retained.
pub fn verify_export(contract : Contract, observation : Observation) -> Report {
  let findings : Array[Finding] = []
  let declared : Map[String, Metric] = Map([])
  let seen : Map[String, Unit] = Map([])
  for metric in contract.metrics {
    declared[metric.name] = metric
  }
  for i, metric in observation.metrics {
    seen[metric.name] = ()
    let location = observation.source + "#/descriptors/\{i}"
    match declared.get(metric.name) {
      Some(expected) => compare_metric(expected, metric, location, findings)
      None =>
        findings.push(
          finding(
            if contract.complete {
              Breaking
            } else {
              Unknown
            },
            "undeclared-observation",
            metric.name,
            location,
            "observed family has no declaration in the supplied contract",
            "declare the family or correct the exporter output",
          ),
        )
    }
  }
  for metric in contract.metrics {
    if !seen.contains(metric.name) {
      findings.push(
        finding(
          Unknown,
          "unobserved-metric",
          metric.name,
          observation.source,
          "declared family was not observed in this scrape",
          "exercise the code path that emits the family; do not infer deletion from this scrape",
        ),
      )
    }
  }
  if !contract.complete {
    findings.push(
      finding(
        Unknown,
        "inventory-incomplete",
        "",
        "/complete",
        "the declaration does not cover the full exporter inventory",
        "supply an exhaustive contract to complete this check",
      ),
    )
  }
  report("observed-export-only", findings)
}
