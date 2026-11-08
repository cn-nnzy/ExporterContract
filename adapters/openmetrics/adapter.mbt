///|
pub suberror ExportError {
  ExportError(String, String, String)
}

///|
fn refuse(
  code : String,
  location : String,
  message : String,
) -> Unit raise ExportError {
  raise ExportError(code, location, message)
}

///|
fn label_names(labels : Array[@om.Label], bucket~ : Bool) -> Array[String] {
  labels.filter_map(l => {
    if bucket && l.name == "le" {
      None
    } else {
      Some(l.name)
    }
  })
}

///|
fn group_key(labels : Array[@om.Label], bucket~ : Bool) -> String {
  let labels = labels.filter(l => !bucket || l.name != "le")
  labels.sort_by((a, b) => a.name.compare(b.name))
  @om.encode_label_set(labels)
}

///|
fn descriptor(
  name : String,
  kind : @contract.MetricKind,
  labels : Array[String],
  unit : String?,
  buckets : Array[Double],
  source : String,
) -> @contract.Metric raise ExportError {
  @contract.Metric::new(name, kind, labels, unit?, buckets~) catch {
    @contract.ContractError(code, _, message) =>
      raise ExportError(code, source + "#" + name, message)
  }
}

///|
/// Read a bounded OpenMetrics 1.0 scrape into observed descriptors.
/// Only counter, gauge, and classic histogram families without explicit
/// timestamps or exemplars are supported. Unsupported data rejects the entire input.
pub fn read_export(
  text : String,
  source~ : String,
) -> @contract.Observation raise ExportError {
  if text.length() > 2097152 {
    refuse("input-limit", source, "scrape exceeds 2097152 UTF-16 code units")
  }
  let document = match @om.parse(text) {
    Ok(value) => value
    Err(error) =>
      raise ExportError(
        "invalid-openmetrics",
        source + ":\{error.line}:\{error.column}",
        "invalid OpenMetrics text; check quoting, separators, and numeric syntax",
      )
  }
  if document.families.length() > 10000 {
    refuse(
      "family-limit", source, "at most 10000 metric families are supported",
    )
  }
  let mut total_samples = 0
  for family in document.families {
    total_samples += family.samples.length()
    if family.samples.length() > 4096 || total_samples > 20000 {
      refuse(
        "sample-limit",
        source + "#" + family.name,
        "at most 4096 samples per family and 20000 per scrape are supported",
      )
    }
  }
  let validation = @om.validate(document)
  for issue in validation.issues {
    // HELP text is outside the descriptor contract; its absence is harmless.
    if issue.code != "missing_help" {
      refuse(
        "invalid-openmetrics:" + issue.code,
        source + "#" + issue.family,
        "correct the OpenMetrics rule violation identified by this code before contract checking",
      )
    }
  }
  let metrics : Array[@contract.Metric] = []
  for family in document.families {
    let kind = match family.metric_type {
      Counter => @contract.Counter
      Gauge => @contract.Gauge
      Histogram => @contract.Histogram
      _ =>
        raise ExportError(
          "unsupported-kind",
          source + "#" + family.name,
          "this profile supports counter, gauge, and classic histogram only",
        )
    }
    let groups : Map[String, Array[String]] = Map([])
    let bounds : Map[String, Array[Double]] = Map([])
    for sample in family.samples {
      if sample.timestamp is Some(_) || sample.exemplar is Some(_) {
        refuse(
          "unsupported-sample-metadata",
          source + "#" + family.name,
          "explicit sample timestamps and exemplars are not supported by this observation profile",
        )
      }
      if sample.name == family.name + "_created" {
        refuse(
          "unsupported-created",
          source + "#" + family.name,
          "created-time series require a dedicated observation profile",
        )
      }
      let key = group_key(sample.labels, bucket=kind == @contract.Histogram)
      groups[key] = label_names(
        sample.labels,
        bucket=kind == @contract.Histogram,
      )
      if kind == @contract.Histogram && sample.name == family.name + "_bucket" {
        let raw = match sample.label("le") {
          Some(raw) => raw
          None =>
            raise ExportError(
              "missing-bound",
              source + "#" + family.name,
              "histogram buckets require an le label",
            )
        }
        let bound = match @om.parse_number(raw) {
          Ok(value) => value
          Err(_) =>
            raise ExportError(
              "invalid-bound",
              source + "#" + family.name,
              "histogram bound must be a number or +Inf",
            )
        }
        if bound.is_finite() {
          match bounds.get(key) {
            Some(values) => values.push(bound)
            None => bounds[key] = [bound]
          }
        } else if !bound.is_pos_inf() {
          refuse(
            "unsupported-bound",
            source + "#" + family.name,
            "only finite histogram bounds and +Inf are supported",
          )
        }
      }
    }
    let keys = groups.keys().collect()
    keys.sort()
    for key in keys {
      let values = bounds.get(key).unwrap_or([])
      values.sort_by((a, b) => a.compare(b))
      metrics.push(
        descriptor(family.name, kind, groups[key], family.unit, values, source),
      )
    }
  }
  @contract.Observation::new(source, metrics) catch {
    @contract.ContractError(code, _, message) =>
      raise ExportError(code, source, message)
  }
}
