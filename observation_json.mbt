///|
/// Serialize only descriptor evidence, never original sample or label values.
pub fn Observation::to_json(self : Observation) -> Json {
  {
    "version": 1,
    "profile": "descriptor-only-v1",
    "source": self.source,
    "descriptors": Json(self.metrics.map(descriptor_json)),
  }
}

///|
/// Read a descriptor-only evidence record. It cannot establish completeness
/// or replace wire-format validation of an original scrape.
pub fn read_observation(source : String) -> Observation raise ContractError {
  if source.length() > 2097152 {
    refuse("input-limit", "/", "observation record exceeds 2097152 code units")
  }
  let value = @json.parse(
    source,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
  ) catch {
    _ =>
      raise ContractError(
        "invalid-observation-json", "/", "provide complete observation JSON with unique keys and at most 32 nesting levels",
      )
  }
  let fields = object(value, "", ["version", "profile", "source", "descriptors"])
  match required(fields, "version", "") {
    Number(v, ..) if v == 1.0 => ()
    _ =>
      refuse(
        "unsupported-observation-version", "/version", "record version must be 1",
      )
  }
  if text(required(fields, "profile", ""), "/profile") != "descriptor-only-v1" {
    refuse(
      "unsupported-observation-profile", "/profile", "only descriptor-only-v1 records are supported",
    )
  }
  let origin = text(required(fields, "source", ""), "/source")
  let metrics = match required(fields, "descriptors", "") {
    Array(items) =>
      items.mapi((i, item) => parse_metric(item, "/descriptors/\{i}"))
    _ =>
      raise ContractError(
        "expected-array", "/descriptors", "provide observed descriptors in their original order",
      )
  }
  Observation::new(origin, metrics)
}
