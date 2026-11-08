///|
test "descriptor diff captures exact definitions and reverses without rename guesses" {
  let a = @exportercontract.Metric::new("a", Gauge, ["route"])
  let modified = @exportercontract.Metric::new("a", Gauge, [])
  let removed = @exportercontract.Metric::new("b", Counter, [])
  let added = @exportercontract.Metric::new("c", Gauge, [])
  let before = contract([removed, a])
  let after = contract([added, modified], complete=false)
  let diff = fields_of(@exportercontract.contract_diff(before, after))
  assert_eq(diff["complete_before"], Json::boolean(true))
  assert_eq(diff["complete_after"], Json::boolean(false))
  guard diff["changes"] is Array(changes) else { fail("expected changes") }
  guard fields_of(@exportercontract.contract_diff(after, before))["changes"]
    is Array(reverse) else {
    fail("expected reverse")
  }
  assert_eq(changes.length(), 3)
  for i in 0..<3 {
    let x = fields_of(changes[i])
    let y = fields_of(reverse[i])
    assert_eq(x["before"], y["after"])
    assert_eq(x["after"], y["before"])
  }
  assert_eq(fields_of(changes[1])["after"], Json::null())
  assert_eq(fields_of(changes[2])["before"], Json::null())
  let reordered = contract([a, removed])
  assert_eq(
    @exportercontract.contract_diff(reordered, after),
    @exportercontract.contract_diff(before, after),
  )
}

///|
test "no-op diff stays empty and unrelated exporters refuse comparison" {
  let c = contract([])
  assert_eq(
    fields_of(@exportercontract.contract_diff(c, c))["changes"],
    Json(([] : Array[Json])),
  )
  try
    @exportercontract.contract_diff(
      c,
      @exportercontract.Contract::new("other", [], complete=true),
    )
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "exporter-mismatch")
  } noraise {
    _ => fail("expected scope mismatch")
  }
}
