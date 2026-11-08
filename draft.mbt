///|
/// Prepare an incomplete declaration for human review. Every observed schema
/// for a family must agree; label sets and bucket layouts are never unioned.
/// An observation does not establish a complete inventory, even if all tests ran.
///
/// ```mbt check
/// test {
///   let m = @exportercontract.Metric::new("active", Gauge, [])
///   let o = @exportercontract.Observation::new("startup", [m])
///   let draft = @exportercontract.draft_contract("service", [o])
///   assert_false(draft.is_complete())
///   assert_eq(@exportercontract.read_contract(draft.to_text()), draft)
/// }
/// ```
pub fn draft_contract(
  exporter : String,
  observations : Array[Observation],
) -> Contract raise ContractError {
  let observations = checked_observations(observations)
  let metrics : Map[String, Metric] = Map([])
  let origins : Map[String, String] = Map([])
  for observation in observations {
    for i, metric in observation.metrics {
      let location = observation.source + "#/descriptors/\{i}"
      match metrics.get(metric.name) {
        Some(previous) =>
          if previous != metric {
            refuse(
              "conflicting-observed-schema",
              location,
              "family \{metric.name} differs from its schema at \{origins[metric.name]}; resolve kind, unit, labels, or bucket disagreement before drafting",
            )
          }
        None => {
          metrics[metric.name] = metric
          origins[metric.name] = location
        }
      }
    }
  }
  if metrics.is_empty() {
    refuse(
      "empty-draft", "/observations", "exercise at least one emitting path before preparing a declaration",
    )
  }
  Contract::new(exporter, metrics.values().collect(), complete=false)
}
