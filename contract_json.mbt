///|
fn object(
  value : Json,
  path : String,
  keys : Array[String],
) -> Map[String, Json] raise ContractError {
  let fields = match value {
    Object(fields) => fields
    _ => raise ContractError("expected-object", path, "expected a JSON object")
  }
  for key, _ in fields {
    if !keys.contains(key) {
      refuse(
        "unknown-field",
        path + "/" + key,
        "field is not supported by contract format version 1",
      )
    }
  }
  fields
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise ContractError {
  match fields.get(key) {
    Some(value) => value
    None =>
      raise ContractError(
        "missing-field",
        path + "/" + key,
        "field must be explicitly declared",
      )
  }
}

///|
fn text(value : Json, path : String) -> String raise ContractError {
  match value {
    String(value) => value
    _ => raise ContractError("expected-string", path, "expected a JSON string")
  }
}

///|
fn kind_name(kind : MetricKind) -> String {
  match kind {
    Counter => "counter"
    Gauge => "gauge"
    Histogram => "histogram"
  }
}

///|
fn parse_metric(value : Json, path : String) -> Metric raise ContractError {
  let fields = object(value, path, ["name", "kind", "unit", "labels", "buckets"])
  let name = text(required(fields, "name", path), path + "/name")
  let kind = match text(required(fields, "kind", path), path + "/kind") {
    "counter" => Counter
    "gauge" => Gauge
    "histogram" => Histogram
    _ =>
      raise ContractError(
        "unsupported-kind",
        path + "/kind",
        "supported kinds are counter, gauge, and classic histogram",
      )
  }
  let unit = match required(fields, "unit", path) {
    Null => None
    String(value) => Some(value)
    _ =>
      raise ContractError(
        "invalid-unit",
        path + "/unit",
        "unit must be explicitly null or an identifier",
      )
  }
  let labels = match required(fields, "labels", path) {
    Array(values) => values.mapi((i, v) => text(v, path + "/labels/\{i}"))
    _ =>
      raise ContractError(
        "expected-array",
        path + "/labels",
        "declare the complete array of label names",
      )
  }
  let buckets = match fields.get("buckets") {
    None => []
    Some(Array(values)) =>
      values.mapi((i, v) => {
        match v {
          Number(value, ..) => value
          _ =>
            raise ContractError(
              "expected-number",
              path + "/buckets/\{i}",
              "bucket bounds must be finite JSON numbers",
            )
        }
      })
    _ =>
      raise ContractError(
        "expected-array",
        path + "/buckets",
        "expected an array of finite bounds",
      )
  }
  Metric::new(name, kind, labels, unit?, buckets~) catch {
    ContractError(code, _, message) => raise ContractError(code, path, message)
  }
}

///|
/// Read contract format version 1. Unknown fields and duplicate keys are errors.
pub fn read_contract(source : String) -> Contract raise ContractError {
  if source.length() > 2097152 {
    refuse(
      "input-limit", "/", "contract input exceeds 2097152 UTF-16 code units",
    )
  }
  let value = @json.parse(
    source,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
  ) catch {
    _ =>
      raise ContractError(
        "invalid-json", "/", "provide complete JSON with unique keys, valid escapes, and at most 32 nesting levels",
      )
  }
  let fields = object(value, "", ["version", "exporter", "complete", "metrics"])
  match required(fields, "version", "") {
    Number(value, ..) if value == 1.0 => ()
    _ =>
      refuse(
        "unsupported-version", "/version", "contract format version must be 1",
      )
  }
  let exporter = text(required(fields, "exporter", ""), "/exporter")
  let complete = match required(fields, "complete", "") {
    True => true
    False => false
    _ =>
      raise ContractError(
        "expected-boolean", "/complete", "explicitly declare whether the metric inventory is exhaustive",
      )
  }
  let metrics = match required(fields, "metrics", "") {
    Array(values) => values.mapi((i, v) => parse_metric(v, "/metrics/\{i}"))
    _ =>
      raise ContractError(
        "expected-array", "/metrics", "expected an array of metric descriptors",
      )
  }
  Contract::new(exporter, metrics, complete~)
}

///|
/// Canonical contract JSON. Metric and label order is normalized.
pub fn Contract::to_json(self : Contract) -> Json {
  {
    "version": 1,
    "exporter": self.exporter,
    "complete": self.complete,
    "metrics": self.metrics.map(m => {
      let fields : Map[String, Json] = {
        "name": Json::string(m.name),
        "kind": Json::string(kind_name(m.kind)),
        "unit": match m.unit {
          Some(v) => Json::string(v)
          None => Json::null()
        },
        "labels": Json(m.labels),
      }
      if m.kind == Histogram {
        fields["buckets"] = Json(m.buckets)
      }
      Json::object(fields)
    }),
  }
}

///|
pub fn Contract::to_text(self : Contract) -> String {
  self.to_json().stringify(indent=2) + "\n"
}
