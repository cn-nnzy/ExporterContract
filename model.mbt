///|
#derive(Debug, Eq)
pub(all) enum MetricKind {
  Counter
  Gauge
  Histogram
}

///|
pub extend MetricKind with Eq::{equal, not_equal}

///|
pub extend MetricKind with @debug.Debug::{to_repr}

///|
pub suberror ContractError {
  ContractError(String, String, String)
}

///|
/// A validated descriptor. Arrays are copied at the API boundary.
#derive(Debug, Eq)
pub struct Metric {
  priv name : String
  priv kind : MetricKind
  priv labels : Array[String]
  priv unit : String?
  priv buckets : Array[Double]
}

///|
pub extend Metric with Eq::{equal, not_equal}

///|
pub extend Metric with @debug.Debug::{to_repr}

///|
/// A declared inventory, not an inventory inferred from one scrape.
#derive(Debug, Eq)
pub struct Contract {
  priv exporter : String
  priv complete : Bool
  priv metrics : Array[Metric]
}

///|
pub extend Contract with Eq::{equal, not_equal}

///|
pub extend Contract with @debug.Debug::{to_repr}

///|
/// Descriptors actually seen in a scrape; absence is never deletion evidence.
#derive(Debug, Eq)
pub struct Observation {
  priv source : String
  priv metrics : Array[Metric]
}

///|
pub extend Observation with Eq::{equal, not_equal}

///|
pub extend Observation with @debug.Debug::{to_repr}

///|
fn refuse(
  code : String,
  path : String,
  message : String,
) -> Unit raise ContractError {
  raise ContractError(code, path, message)
}

///|
fn lexical(a : String, b : String) -> Int32 {
  let length = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<length {
    if a[i] < b[i] {
      return -1
    }
    if a[i] > b[i] {
      return 1
    }
  }
  a.length().compare(b.length())
}

///|
fn valid_name(name : String, metric~ : Bool) -> Bool {
  if name == "" || name.length() > 256 {
    return false
  }
  for i in 0..<name.length() {
    let c = name[i]
    if !(c is ('a'..<='z') ||
      c is ('A'..<='Z') ||
      c == '_' ||
      (metric && c == ':') ||
      (i > 0 && c is ('0'..<='9'))) {
      return false
    }
  }
  true
}

///|
/// Construct a metric using the OpenMetrics family name, without `_total` for counters.
/// Histogram bounds are finite bounds only; +Inf is implicit.
pub fn Metric::new(
  name : String,
  kind : MetricKind,
  labels : Array[String],
  unit? : String,
  buckets~ : Array[Double] = [],
) -> Metric raise ContractError {
  if !valid_name(name, metric=true) {
    refuse(
      "invalid-metric-name", name, "use an ASCII OpenMetrics family name of at most 256 code units",
    )
  }
  if labels.length() > 64 {
    refuse(
      "label-limit", name, "at most 64 label names are supported per descriptor",
    )
  }
  let labels = labels.map(x => x)
  labels.sort_by(lexical)
  for i, label in labels {
    if !valid_name(label, metric=false) ||
      label.has_prefix("__") ||
      label == "le" ||
      label == "quantile" {
      refuse(
        "invalid-label-name", name, "label names must be valid, non-reserved ASCII names",
      )
    }
    if i > 0 && labels[i - 1] == label {
      refuse("duplicate-label", name, "each label name must occur once")
    }
  }
  if unit is Some(value) && !valid_name(value, metric=false) {
    refuse(
      "invalid-unit", name, "unit must be null or a non-empty ASCII identifier",
    )
  }
  if buckets.length() > 256 {
    refuse(
      "bucket-limit", name, "at most 256 finite histogram bounds are supported",
    )
  }
  if kind != Histogram && buckets.length() > 0 {
    refuse(
      "unexpected-buckets", name, "only histogram descriptors may declare buckets",
    )
  }
  if kind == Histogram && buckets.length() == 0 {
    refuse(
      "missing-buckets", name, "histograms must declare at least one finite bucket bound",
    )
  }
  for i, bound in buckets {
    if !bound.is_finite() {
      refuse(
        "nonfinite-bucket", name, "declare finite bounds only; +Inf is implicit",
      )
    }
    if i > 0 && buckets[i - 1] >= bound {
      refuse(
        "unordered-buckets", name, "histogram bounds must be strictly increasing",
      )
    }
  }
  // Signed zero is one numeric bound; normalize it for canonical serialization.
  {
    name,
    kind,
    labels,
    unit,
    buckets: buckets.map(x => if x == 0.0 { 0.0 } else { x }),
  }
}

///|
pub fn Metric::name(self : Metric) -> String {
  self.name
}

///|
pub fn Metric::kind(self : Metric) -> MetricKind {
  self.kind
}

///|
pub fn Metric::labels(self : Metric) -> Array[String] {
  self.labels.map(x => x)
}

///|
pub fn Metric::unit(self : Metric) -> String? {
  self.unit
}

///|
pub fn Metric::buckets(self : Metric) -> Array[Double] {
  self.buckets.map(x => x)
}

///|
fn sample_names(metric : Metric) -> Array[String] {
  match metric.kind {
    Counter => [metric.name + "_total", metric.name + "_created"]
    Gauge => [metric.name]
    Histogram =>
      [
        metric.name + "_bucket",
        metric.name + "_count",
        metric.name + "_sum",
        metric.name + "_created",
      ]
  }
}

///|
/// Construct an explicit contract. `complete` declares whether its family inventory is exhaustive.
pub fn Contract::new(
  exporter : String,
  metrics : Array[Metric],
  complete~ : Bool,
) -> Contract raise ContractError {
  if exporter.trim().is_empty() || exporter.length() > 256 {
    refuse(
      "invalid-exporter", "/exporter", "exporter must be a non-empty identifier of at most 256 code units",
    )
  }
  if metrics.length() > 10000 {
    refuse(
      "metric-limit", "/metrics", "at most 10000 metric families are supported",
    )
  }
  let metrics = metrics.map(x => x)
  metrics.sort_by((a, b) => lexical(a.name, b.name))
  let owners : Map[String, String] = Map([])
  for i, metric in metrics {
    if i > 0 && metrics[i - 1].name == metric.name {
      refuse(
        "duplicate-metric",
        metric.name,
        "metric family names must be unique",
      )
    }
    let names = sample_names(metric)
    names.push(metric.name)
    for sample in names {
      match owners.get(sample) {
        Some(owner) =>
          if owner != metric.name {
            refuse(
              "sample-name-collision",
              metric.name,
              "generated sample names collide with another family",
            )
          }
        None => owners[sample] = metric.name
      }
    }
  }
  { exporter, complete, metrics, }
}

///|
pub fn Contract::exporter(self : Contract) -> String {
  self.exporter
}

///|
pub fn Contract::is_complete(self : Contract) -> Bool {
  self.complete
}

///|
pub fn Contract::metrics(self : Contract) -> Array[Metric] {
  self.metrics.map(x => x)
}

///|
/// Construct observed descriptors. Repeated family names represent separate label groups.
pub fn Observation::new(
  source : String,
  metrics : Array[Metric],
) -> Observation raise ContractError {
  if source.trim().is_empty() || source.length() > 1024 {
    refuse(
      "invalid-source", "/source", "supply a non-empty source identifier of at most 1024 code units",
    )
  }
  if metrics.length() > 100000 {
    refuse(
      "observation-limit", source, "at most 100000 observed descriptors are supported",
    )
  }
  { source, metrics: metrics.map(x => x), }
}

///|
pub fn Observation::source(self : Observation) -> String {
  self.source
}
