///|
test "composition is commutative idempotent and preserves incomplete evidence" {
  let a = contract(
    [@exportercontract.Metric::new("a", Gauge, [])],
    complete=false,
  )
  let b = contract(
    [@exportercontract.Metric::new("b", Counter, [])],
    complete=false,
  )
  let result = @exportercontract.combine_contracts([a, b, a])
  assert_false(result.is_complete())
  assert_eq(result.metrics().length(), 2)
  assert_eq(
    result.to_text(),
    @exportercontract.combine_contracts([b, a]).to_text(),
  )
  assert_eq(@exportercontract.combine_contracts([a, a]), a)
  assert_eq(@exportercontract.read_contract(result.to_text()), result)
}

///|
test "complete declarations cannot contradict each other or partial fragments" {
  let a = @exportercontract.Metric::new("a", Gauge, [])
  let b = @exportercontract.Metric::new("b", Gauge, [])
  let full = contract([a])
  for
    parts in [
      [full, contract([b])],
      [full, contract([b], complete=false)],
      [contract([b], complete=false), full],
    ] {
    try @exportercontract.combine_contracts(parts) catch {
      @exportercontract.ContractError(code, _, _) =>
        assert_eq(code, "contradictory-inventory")
    } noraise {
      _ => fail("expected contradictory completeness refusal")
    }
  }
  let result = @exportercontract.combine_contracts([
    full,
    contract([a], complete=false),
  ])
  assert_false(result.is_complete())
  assert_eq(result.metrics(), [a])
}

///|
test "composition rejects ambiguity collisions exporter mismatch and empty input" {
  let a = contract([@exportercontract.Metric::new("a", Gauge, [])])
  let bad = contract([@exportercontract.Metric::new("a", Gauge, ["route"])])
  let counter = contract([
    @exportercontract.Metric::new("requests", Counter, []),
  ])
  let wire = contract([
    @exportercontract.Metric::new("requests_total", Gauge, []),
  ])
  let other = @exportercontract.Contract::new("other", [], complete=true)
  for parts in [[], [a, bad], [counter, wire], [a, other], Array::make(65, a)] {
    try @exportercontract.combine_contracts(parts) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected composition refusal")
    }
  }
  assert_eq(@exportercontract.combine_contracts([a]), a)
}
