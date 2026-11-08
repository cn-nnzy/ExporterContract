///|
test "complementary observations cover declarations with explicit provenance" {
  let active = @exportercontract.Metric::new("active", Gauge, [])
  let requests = @exportercontract.Metric::new("requests", Counter, ["method"])
  let c = contract([active, requests])
  let startup = @exportercontract.Observation::new("startup.om", [
    active, active,
  ])
  let traffic = @exportercontract.Observation::new("traffic.om", [requests])
  assert_eq(@exportercontract.verify_export(c, startup).verdict(), Inconclusive)
  let result = @exportercontract.verify_exports(c, [traffic, startup])
  assert_eq(result.report().verdict(), Compatible)
  assert_eq(result.report().scope(), "observed-exports-only")
  assert_eq(result.sources(), ["startup.om", "traffic.om"])
  assert_eq(result.coverage()[0].metric, "active")
  assert_eq(result.coverage()[0].sources(), ["startup.om"])
  assert_eq(result.coverage()[1].sources(), ["traffic.om"])
  assert_eq(
    result.to_json(),
    @exportercontract.verify_exports(c, [startup, traffic]).to_json(),
  )
  result.sources().clear()
  result.coverage()[0].sources().clear()
  result.coverage().clear()
  assert_eq(result.coverage().length(), 2)
  assert_eq(result.coverage()[0].sources(), ["startup.om"])
  assert_eq(result.sources().length(), 2)
}

///|
test "later conforming evidence cannot hide any earlier violation" {
  let good = @exportercontract.Metric::new("active", Gauge, [])
  let bad = @exportercontract.Metric::new("active", Gauge, ["route"])
  let observations = [
    @exportercontract.Observation::new("bad.om", [bad]),
    @exportercontract.Observation::new("good.om", [good]),
  ]
  let result = @exportercontract.verify_exports(contract([good]), observations)
  assert_eq(result.report().verdict(), Incompatible)
  assert_eq(result.report().findings()[0].code, "label-added")
  assert_true(result.report().findings()[0].location.has_prefix("bad.om#"))
  assert_eq(result.coverage()[0].sources(), ["bad.om", "good.om"])
}

///|
test "batch absence and incomplete declarations remain unknown" {
  let a = @exportercontract.Metric::new("active", Gauge, [])
  let observations = [@exportercontract.Observation::new("empty.om", [])]
  let result = @exportercontract.verify_exports(contract([a]), observations)
  assert_eq(result.report().verdict(), Inconclusive)
  assert_eq(result.coverage()[0].sources(), [])
  assert_eq(result.report().findings()[0].code, "unobserved-metric")
  let partial = @exportercontract.verify_exports(
    contract([a], complete=false),
    [@exportercontract.Observation::new("full.om", [a])],
  )
  assert_eq(partial.report().verdict(), Inconclusive)
  assert_eq(partial.report().findings().map(f => f.code), [
    "inventory-incomplete",
  ])
}

///|
test "batch admission rejects ambiguous and excessive evidence then recovers" {
  let c = contract([])
  let observation = @exportercontract.Observation::new("same.om", [])
  for
    observations in [
      [],
      [observation, observation],
      Array::make(65, observation),
    ] {
    try @exportercontract.verify_exports(c, observations) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected batch rejection")
    }
  }
  let m = @exportercontract.Metric::new("active", Gauge, [])
  let large = Array::make(50001, m)
  try
    @exportercontract.verify_exports(c, [
      @exportercontract.Observation::new("a", large),
      @exportercontract.Observation::new("b", large),
    ])
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "batch-descriptor-limit")
  } noraise {
    _ => fail("expected aggregate limit")
  }
  assert_eq(
    @exportercontract.verify_exports(c, [observation]).report().verdict(),
    Compatible,
  )
  assert_eq(
    @exportercontract.verify_exports(
      c,
      Array::makei(64, i => {
        @exportercontract.Observation::new("source_\{i}", [])
      }),
    )
    .sources()
    .length(),
    64,
  )
}
