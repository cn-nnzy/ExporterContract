///|
fn contract(
  metrics : Array[@exportercontract.Metric],
  complete~ : Bool = true,
) -> @exportercontract.Contract raise {
  @exportercontract.Contract::new("api", metrics, complete~)
}

///|
test "identical complete declarations pass and additive families are notices" {
  let a = @exportercontract.Metric::new("active", Gauge, [])
  let b = @exportercontract.Metric::new("requests", Counter, [])
  let base = contract([a])
  let unchanged = @exportercontract.compare_contracts(base, base)
  assert_eq(unchanged.verdict(), Compatible)
  assert_eq(unchanged.findings().length(), 0)
  let additive = @exportercontract.compare_contracts(base, contract([a, b]))
  assert_eq(additive.verdict(), Compatible)
  assert_eq(additive.findings()[0].code, "metric-added")
  assert_eq(additive.findings()[0].severity, Notice)
}

///|
test "stable schema changes have distinct actionable findings" {
  let before = contract([
    @exportercontract.Metric::new("active", Gauge, ["route"], unit="seconds"),
    @exportercontract.Metric::new("latency", Histogram, [], buckets=[0.1, 1.0]),
  ])
  let after = contract([
    @exportercontract.Metric::new("active", Counter, ["method"], unit="bytes"),
    @exportercontract.Metric::new("latency", Histogram, [], buckets=[0.5, 1.0]),
  ])
  let result = @exportercontract.compare_contracts(before, after)
  assert_eq(result.verdict(), Incompatible)
  assert_eq(result.findings().map(f => f.code), [
    "kind-changed", "label-added", "label-removed", "unit-changed", "buckets-changed",
  ])
  for finding in result.findings() {
    assert_true(finding.remedy.length() > 0)
  }
  assert_eq(
    @exportercontract.compare_contracts(before, after).to_json(),
    result.to_json(),
  )
  result.findings().clear()
  assert_eq(result.findings().length(), 5)
}

///|
test "partial inventory absence is inconclusive rather than deletion" {
  let metric = @exportercontract.Metric::new("active", Gauge, [])
  let before = contract([metric])
  let partial = @exportercontract.compare_contracts(
    before,
    contract([], complete=false),
  )
  assert_eq(partial.verdict(), Inconclusive)
  assert_eq(partial.findings().map(f => f.code), [
    "inventory-incomplete", "presence-unproven",
  ])
  let removed = @exportercontract.compare_contracts(before, contract([]))
  assert_eq(removed.verdict(), Incompatible)
  assert_eq(removed.findings()[0].code, "metric-removed")
}

///|
test "renames are explicit removal and addition and exporters cannot be mixed" {
  let old = contract([@exportercontract.Metric::new("old", Gauge, [])])
  let new = contract([@exportercontract.Metric::new("new", Gauge, [])])
  let report = @exportercontract.compare_contracts(old, new)
  assert_eq(report.findings().map(f => f.code), [
    "metric-added", "metric-removed",
  ])
  let unrelated = @exportercontract.Contract::new(
    "another-api",
    [],
    complete=true,
  )
  try @exportercontract.compare_contracts(old, unrelated) catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "exporter-mismatch")
  } noraise {
    _ => fail("expected exporter mismatch")
  }
}

///|
test "observations do not establish deletion or whole-exporter completeness" {
  let m = @exportercontract.Metric::new("active", Gauge, ["route"])
  let declared = contract([m])
  let empty = @exportercontract.Observation::new("scrape.om", [])
  let missing = @exportercontract.verify_export(declared, empty)
  assert_eq(missing.verdict(), Inconclusive)
  assert_eq(missing.findings()[0].code, "unobserved-metric")
  let observed = @exportercontract.verify_export(
    declared,
    @exportercontract.Observation::new("scrape.om", [m]),
  )
  assert_eq(observed.verdict(), Compatible)
  assert_eq(observed.scope(), "observed-export-only")
  let extra = @exportercontract.Metric::new("unknown", Gauge, [])
  let bad = @exportercontract.verify_export(
    declared,
    @exportercontract.Observation::new("scrape.om", [extra]),
  )
  assert_eq(bad.verdict(), Incompatible)
  let partial = @exportercontract.verify_export(
    contract([], complete=false),
    @exportercontract.Observation::new("scrape.om", [extra]),
  )
  assert_eq(partial.verdict(), Inconclusive)
}

///|
test "metric and label permutations cannot change contract decisions" {
  let a = @exportercontract.Metric::new("a", Gauge, ["method", "zone"])
  let b = @exportercontract.Metric::new("b", Counter, [])
  let c = @exportercontract.Metric::new("c", Gauge, [])
  let baseline = contract([a, b, c])
  let expected = @exportercontract.compare_contracts(baseline, contract([a, b])).to_text()
  for
    ordering in [
      [a, b, c],
      [a, c, b],
      [b, a, c],
      [b, c, a],
      [c, a, b],
      [c, b, a],
    ] {
    let input = contract(ordering)
    assert_eq(input.to_text(), baseline.to_text())
    assert_eq(
      @exportercontract.compare_contracts(input, contract([b, a])).to_text(),
      expected,
    )
  }
}
