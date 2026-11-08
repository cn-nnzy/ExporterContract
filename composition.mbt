///|
/// Combine declarations for the same exporter without choosing a conflict winner.
/// Completeness requires every input to be explicitly complete.
pub fn combine_contracts(
  parts : Array[Contract],
) -> Contract raise ContractError {
  if parts.is_empty() || parts.length() > 64 {
    refuse(
      "contract-batch-size", "/contracts", "supply between 1 and 64 declarations",
    )
  }
  let exporter = parts[0].exporter
  let metrics : Map[String, Metric] = Map([])
  let mut complete = true
  for part in parts {
    if part.exporter != exporter {
      refuse(
        "exporter-mismatch", "/exporter", "only combine declarations for the same exporter scope",
      )
    }
    complete = complete && part.complete
    for metric in part.metrics {
      match metrics.get(metric.name) {
        Some(previous) =>
          if previous != metric {
            refuse(
              "conflicting-declaration",
              metric.name,
              "resolve differing descriptors before combining declarations",
            )
          }
        None => metrics[metric.name] = metric
      }
      if metrics.length() > 10000 {
        refuse(
          "metric-limit", "/metrics", "combined inventory exceeds 10000 families",
        )
      }
    }
  }
  Contract::new(exporter, metrics.values().collect(), complete~)
}
