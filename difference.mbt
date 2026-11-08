///|
fn descriptor_json(metric : Metric) -> Json {
  let value = Contract::to_json({
    exporter: "descriptor",
    complete: false,
    metrics: [metric],
  })
  match value {
    Object(fields) =>
      match fields["metrics"] {
        Array(items) => items[0]
        _ => abort("invalid internal encoding")
      }
    _ => abort("invalid internal encoding")
  }
}

///|
/// Describe exact added, removed and modified schemas for release review.
/// This artifact is not a compatibility verdict; use compare_contracts for policy.
pub fn contract_diff(
  before : Contract,
  after : Contract,
) -> Json raise ContractError {
  if before.exporter != after.exporter {
    refuse(
      "exporter-mismatch", "/exporter", "diff declarations for the same exporter scope",
    )
  }
  let old : Map[String, Metric] = Map([])
  let current : Map[String, Metric] = Map([])
  let names : Map[String, Unit] = Map([])
  for m in before.metrics {
    old[m.name] = m
    names[m.name] = ()
  }
  for m in after.metrics {
    current[m.name] = m
    names[m.name] = ()
  }
  let sorted = names.keys().collect()
  sorted.sort_by(lexical)
  let changes : Array[Json] = []
  for name in sorted {
    let previous = old.get(name)
    let next = current.get(name)
    if previous != next {
      changes.push({
        "metric": name,
        "before": match previous {
          Some(m) => descriptor_json(m)
          None => Json::null()
        },
        "after": match next {
          Some(m) => descriptor_json(m)
          None => Json::null()
        },
      })
    }
  }
  {
    "version": 1,
    "exporter": before.exporter,
    "complete_before": before.complete,
    "complete_after": after.complete,
    "changes": Json(changes),
  }
}
