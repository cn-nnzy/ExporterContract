///|
/// Read strict coverage-plan format 1. Requirements are validated against a
/// declaration and observation batch by verify_required_sources.
pub fn read_coverage_plan(
  source : String,
) -> Map[String, Array[String]] raise ContractError {
  if source.length() > 2097152 {
    refuse("input-limit", "/", "coverage plan exceeds 2097152 code units")
  }
  let value = @json.parse(
    source,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
  ) catch {
    _ =>
      raise ContractError(
        "invalid-plan-json", "/", "provide complete coverage-plan JSON with unique keys and at most 32 nesting levels",
      )
  }
  let fields = object(value, "", ["version", "requirements"])
  match required(fields, "version", "") {
    Number(v, ..) if v == 1.0 => ()
    _ =>
      refuse(
        "unsupported-plan-version", "/version", "coverage plan version must be 1",
      )
  }
  let entries = match required(fields, "requirements", "") {
    Object(entries) => entries
    _ =>
      raise ContractError(
        "expected-object", "/requirements", "map family names to required source identifiers",
      )
  }
  if entries.is_empty() || entries.length() > 10000 {
    refuse(
      "coverage-plan-size", "/requirements", "supply 1 to 10000 family requirements",
    )
  }
  let result : Map[String, Array[String]] = Map([])
  for name, value in entries {
    let sources = match value {
      Array(items) =>
        items.mapi((i, item) => text(item, "/requirements/" + name + "/\{i}"))
      _ =>
        raise ContractError(
          "expected-array", name, "provide an array of source identifiers",
        )
    }
    if sources.is_empty() || sources.length() > 64 {
      refuse("coverage-source-count", name, "require 1 to 64 distinct sources")
    }
    let seen : Map[String, Unit] = Map([])
    for source in sources {
      let _ = Observation::new(source, [])
      if seen.contains(source) {
        refuse(
          "duplicate-coverage-source", name, "each source must occur once per family",
        )
      }
      seen[source] = ()
    }
    result[name] = sources
  }
  result
}
