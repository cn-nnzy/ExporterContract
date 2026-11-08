///|
test "selection is canonical independent and preserves incomplete declarations" {
  let a = @exportercontract.Metric::new("a", Gauge, [])
  let b = @exportercontract.Metric::new("b", Gauge, [])
  let parent = contract([a, b])
  let selected = @exportercontract.select_contract(
    parent,
    ["b", "a"],
    exporter="subset",
  )
  assert_eq(selected.metrics(), [a, b])
  assert_true(selected.is_complete())
  assert_eq(selected.exporter(), "subset")
  assert_eq(
    selected.to_text(),
    @exportercontract.select_contract(parent, ["a", "b"], exporter="subset").to_text(),
  )
  assert_eq(@exportercontract.read_contract(selected.to_text()), selected)
  let partial = @exportercontract.select_contract(
    contract([a], complete=false),
    ["a"],
    exporter="partial",
  )
  assert_false(partial.is_complete())
  selected.metrics().clear()
  assert_eq(parent.metrics().length(), 2)
}

///|
test "selection refuses missing duplicate empty and ambiguous scopes" {
  let parent = contract([@exportercontract.Metric::new("active", Gauge, [])])
  for names in [[], ["absent"], ["active", "active"]] {
    try
      @exportercontract.select_contract(parent, names, exporter="subset")
    catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected selection refusal")
    }
  }
  for exporter in ["api", " "] {
    try @exportercontract.select_contract(parent, ["active"], exporter~) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid scope")
    }
  }
  assert_eq(
    @exportercontract.select_contract(parent, ["active"], exporter="subset")
    .metrics()
    .length(),
    1,
  )
}
