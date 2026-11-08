///|
test "drafts collect consistent descriptors canonically but stay incomplete" {
  let a = @exportercontract.Metric::new("active", Gauge, ["zone", "route"])
  let b = @exportercontract.Metric::new("requests", Counter, [])
  let observations = [
    @exportercontract.Observation::new("startup", [a, a]),
    @exportercontract.Observation::new("traffic", [b, a]),
  ]
  let draft = @exportercontract.draft_contract("service", observations)
  assert_false(draft.is_complete())
  assert_eq(draft.metrics(), [a, b])
  assert_eq(draft.exporter(), "service")
  assert_eq(@exportercontract.read_contract(draft.to_text()), draft)
  assert_eq(
    @exportercontract.draft_contract("service", [
      observations[1],
      observations[0],
    ]).to_text(),
    draft.to_text(),
  )
  assert_eq(
    @exportercontract.compare_contracts(draft, draft).verdict(),
    Inconclusive,
  )
}

///|
test "drafts refuse each kind of schema disagreement instead of unioning" {
  let baseline = @exportercontract.Metric::new(
    "duration_seconds",
    Histogram,
    ["route"],
    unit="seconds",
    buckets=[0.1, 1.0],
  )
  for
    candidate in [
      @exportercontract.Metric::new(
        "duration_seconds",
        Gauge,
        ["route"],
        unit="seconds",
      ),
      @exportercontract.Metric::new("duration_seconds", Histogram, ["route"], buckets=[
        0.1, 1.0,
      ]),
      @exportercontract.Metric::new(
        "duration_seconds",
        Histogram,
        ["method", "route"],
        unit="seconds",
        buckets=[0.1, 1.0],
      ),
      @exportercontract.Metric::new(
        "duration_seconds",
        Histogram,
        ["route"],
        unit="seconds",
        buckets=[0.5, 1.0],
      ),
    ] {
    try
      @exportercontract.draft_contract("service", [
        @exportercontract.Observation::new("b", [candidate]),
        @exportercontract.Observation::new("a", [baseline]),
      ])
    catch {
      @exportercontract.ContractError(code, path, message) => {
        assert_eq(code, "conflicting-observed-schema")
        assert_eq(path, "b#/descriptors/0")
        assert_true(message.contains("a#/descriptors/0"))
      }
    } noraise {
      _ => fail("expected schema disagreement")
    }
  }
}

///|
test "intra-scrape disagreements and wire-name collisions also refuse drafts" {
  let a = @exportercontract.Metric::new("active", Gauge, [])
  let bad = @exportercontract.Metric::new("active", Gauge, ["route"])
  try
    @exportercontract.draft_contract("service", [
      @exportercontract.Observation::new("single", [a, bad]),
    ])
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "conflicting-observed-schema")
  } noraise {
    _ => fail("expected intra-source disagreement")
  }
  try
    @exportercontract.draft_contract("service", [
      @exportercontract.Observation::new("single", [
        @exportercontract.Metric::new("requests", Counter, []),
        @exportercontract.Metric::new("requests_total", Gauge, []),
      ]),
    ])
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "sample-name-collision")
  } noraise {
    _ => fail("expected collision")
  }
}

///|
test "empty and ambiguous evidence refuses drafts and valid input recovers" {
  let empty = @exportercontract.Observation::new("empty", [])
  for observations in [[], [empty], [empty, empty]] {
    try @exportercontract.draft_contract("service", observations) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected refusal")
    }
  }
  let valid = @exportercontract.Observation::new("valid", [
    @exportercontract.Metric::new("active", Gauge, []),
  ])
  let draft = @exportercontract.draft_contract("service", [empty, valid])
  assert_eq(draft.metrics().length(), 1)
  assert_false(draft.is_complete())
}
