///|
test "specified path requirements cannot be satisfied by another source" {
  let m = @exportercontract.Metric::new("active", Gauge, [])
  let c = contract([m])
  let observations = [@exportercontract.Observation::new("startup", [m])]
  let missing = @exportercontract.verify_required_sources(c, observations, {
    "active": ["traffic"],
  })
  assert_eq(missing.report().verdict(), Inconclusive)
  assert_eq(missing.report().findings()[0].code, "required-source-unobserved")
  assert_eq(missing.report().findings()[0].location, "traffic")
  let good = @exportercontract.verify_required_sources(c, observations, {
    "active": ["startup"],
  })
  assert_eq(good.report().verdict(), Compatible)
  assert_eq(good.report().scope(), "required-source-coverage")
}

///|
test "coverage requirements preserve schema violations and deterministic evidence" {
  let m = @exportercontract.Metric::new("active", Gauge, [])
  let bad = @exportercontract.Metric::new("active", Gauge, ["route"])
  let observations = [
    @exportercontract.Observation::new("a", [bad]),
    @exportercontract.Observation::new("b", [m]),
  ]
  let a = @exportercontract.verify_required_sources(
    contract([m]),
    observations,
    { "active": ["b", "a", "c"] },
  )
  let b = @exportercontract.verify_required_sources(
    contract([m]),
    [observations[1], observations[0]],
    { "active": ["c", "a", "b"] },
  )
  assert_eq(a.to_json(), b.to_json())
  assert_eq(a.report().verdict(), Incompatible)
  assert_true(
    a.report().findings().any(f => f.code == "required-source-unobserved"),
  )
  let declaration = contract([m])
  for
    requirements in [
      {},
      { "unknown": ["a"] },
      { "active": [] },
      { "active": ["a", "a"] },
      { "active": [""] },
    ] {
    try
      @exportercontract.verify_required_sources(
        declaration, observations, requirements,
      )
    catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid coverage requirements")
    }
  }
}
