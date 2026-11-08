///|
/// Extract an explicitly named sub-scope. Never upgrade incomplete evidence.
/// All requested family names must exist and occur exactly once.
pub fn select_contract(
  contract : Contract,
  names : Array[String],
  exporter~ : String,
) -> Contract raise ContractError {
  if exporter == contract.exporter {
    refuse(
      "scope-name-required", "/exporter", "use a different exporter identifier for the selected scope",
    )
  }
  if names.is_empty() || names.length() > 10000 {
    refuse("selection-size", "/metrics", "select between 1 and 10000 families")
  }
  let available : Map[String, Metric] = Map([])
  for m in contract.metrics {
    available[m.name] = m
  }
  let selected : Map[String, Unit] = Map([])
  let metrics = names.map(name => {
    if selected.contains(name) {
      refuse("duplicate-selection", name, "select each family once")
    }
    selected[name] = ()
    match available.get(name) {
      Some(metric) => metric
      None =>
        raise ContractError(
          "unknown-selection", name, "family is not declared; check its OpenMetrics family name",
        )
    }
  })
  Contract::new(exporter, metrics, complete=contract.complete)
}
