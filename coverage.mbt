///|
/// Sources in which a family was observed. This is emission evidence, not path coverage.
pub struct MetricCoverage {
  metric : String
  priv sources : Array[String]
}

///|
pub fn MetricCoverage::sources(self : MetricCoverage) -> Array[String] {
  self.sources.map(x => x)
}

///|
/// A batch verdict and its explicit source-to-family evidence.
pub struct BatchReport {
  priv report : Report
  priv sources : Array[String]
  priv coverage : Array[MetricCoverage]
}

///|
pub fn BatchReport::report(self : BatchReport) -> Report {
  self.report
}

///|
pub fn BatchReport::coverage(self : BatchReport) -> Array[MetricCoverage] {
  self.coverage.map(x => x)
}

///|
pub fn BatchReport::sources(self : BatchReport) -> Array[String] {
  self.sources.map(x => x)
}

///|
pub fn BatchReport::to_json(self : BatchReport) -> Json {
  let value = self.report.to_json()
  if value is Object(fields) {
    fields["sources"] = Json(self.sources)
    fields["coverage"] = Json(
      self.coverage.map(c => {
        ({ "metric": c.metric, "sources": Json(c.sources) } : Json)
      }),
    )
  }
  value
}

///|
pub fn BatchReport::to_text(self : BatchReport) -> String {
  let output = StringBuilder()
  output.write_string(self.report.to_text())
  output.write_string("observed sources: \{Json(self.sources).stringify()}\n")
  for item in self.coverage {
    output.write_string(
      "coverage \{item.metric}: \{Json(item.sources).stringify()}\n",
    )
  }
  output.to_string()
}

///|
fn checked_observations(
  observations : Array[Observation],
) -> Array[Observation] raise ContractError {
  if observations.is_empty() || observations.length() > 64 {
    refuse(
      "batch-size", "/observations", "supply between 1 and 64 observations",
    )
  }
  let sorted = observations.map(x => x)
  sorted.sort_by((a, b) => lexical(a.source, b.source))
  let mut count = 0
  for i, observation in sorted {
    if i > 0 && sorted[i - 1].source == observation.source {
      refuse(
        "duplicate-source",
        observation.source,
        "use distinct source identifiers so evidence remains attributable",
      )
    }
    count += observation.metrics.length()
    if count > 100000 {
      refuse(
        "batch-descriptor-limit", "/observations", "at most 100000 descriptors are supported across the batch",
      )
    }
  }
  sorted
}

///|
/// Check every descriptor in every observation. A family is unobserved only
/// when absent from the whole batch. Sources are distinct; order is immaterial.
/// No number of observations establishes whole-exporter completeness.
///
/// ```mbt check
/// test {
///   let m = @exportercontract.Metric::new("active", Gauge, [])
///   let c = @exportercontract.Contract::new("service", [m], complete=true)
///   let o = @exportercontract.Observation::new("startup", [m])
///   assert_eq(
///     @exportercontract.verify_exports(c, [o]).report().verdict(),
///     Compatible,
///   )
/// }
/// ```
pub fn verify_exports(
  contract : Contract,
  observations : Array[Observation],
) -> BatchReport raise ContractError {
  let observations = checked_observations(observations)
  let findings : Array[Finding] = []
  let seen : Map[String, Array[String]] = Map([])
  for metric in contract.metrics {
    seen[metric.name] = []
  }
  for observation in observations {
    for metric in observation.metrics {
      let sources = match seen.get(metric.name) {
        Some(sources) => sources
        None => {
          let sources = []
          seen[metric.name] = sources
          sources
        }
      }
      if !sources.contains(observation.source) {
        sources.push(observation.source)
      }
    }
    let result = verify_export(contract, observation)
    for item in result.findings {
      if item.code != "unobserved-metric" && item.code != "inventory-incomplete" {
        findings.push(item)
      }
    }
  }
  for metric in contract.metrics {
    if seen[metric.name].is_empty() {
      findings.push(
        finding(
          Unknown,
          "unobserved-metric",
          metric.name,
          "/observations",
          "declared family was not observed in any supplied source",
          "exercise its emitting path; batch absence is not deletion evidence",
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
        "supply an exhaustive declaration; observed coverage cannot prove completeness",
      ),
    )
  }
  let names = seen.keys().collect()
  names.sort_by(lexical)
  {
    report: report("observed-exports-only", findings),
    sources: observations.map(x => x.source),
    coverage: names.map(name => { metric: name, sources: seen[name], }),
  }
}
