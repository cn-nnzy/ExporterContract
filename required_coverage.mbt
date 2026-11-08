///|
/// Require particular families to be emitted by named test sources. Coverage
/// from another source cannot satisfy a requirement. Missing evidence is unknown.
pub fn verify_required_sources(
  contract : Contract,
  observations : Array[Observation],
  requirements : Map[String, Array[String]],
) -> BatchReport raise ContractError {
  let batch = verify_exports(contract, observations)
  let declared : Map[String, Unit] = Map([])
  for m in contract.metrics {
    declared[m.name] = ()
  }
  let evidence : Map[String, Array[String]] = Map([])
  for item in batch.coverage {
    evidence[item.metric] = item.sources
  }
  let findings = batch.report.findings()
  let names = requirements.keys().collect()
  names.sort_by(lexical)
  if names.is_empty() || names.length() > 10000 {
    refuse(
      "coverage-plan-size", "/requirements", "supply 1 to 10000 family requirements",
    )
  }
  for name in names {
    if !declared.contains(name) {
      refuse(
        "unknown-coverage-family", name, "coverage requirements must name declared families",
      )
    }
    let sources = requirements[name].map(x => x)
    if sources.is_empty() || sources.length() > 64 {
      refuse(
        "coverage-source-count", name, "require between 1 and 64 distinct sources per family",
      )
    }
    sources.sort_by(lexical)
    for i, source in sources {
      let _ = Observation::new(source, [])
      if i > 0 && sources[i - 1] == source {
        refuse(
          "duplicate-coverage-source", name, "require each source only once per family",
        )
      }
      if !evidence[name].contains(source) {
        findings.push(
          finding(
            Unknown,
            "required-source-unobserved",
            name,
            source,
            "the required test source did not supply this family",
            "run the named test path and collect the family there; evidence from other sources does not satisfy this requirement",
          ),
        )
      }
    }
  }
  {
    report: report("required-source-coverage", findings),
    sources: batch.sources,
    coverage: batch.coverage,
  }
}
