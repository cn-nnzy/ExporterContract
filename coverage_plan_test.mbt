///|
test "coverage plan parsing is strict and recovers after malformed input" {
  for
    source in [
      "{}", "{\"version\":1,\"version\":1}", "{\"version\":2,\"requirements\":{\"active\":[\"test\"]}}",
      "{\"version\":1,\"requirements\":{}}", "{\"version\":1,\"requirements\":{\"active\":[\"a\",\"a\"]}}",
      "{\"version\":1,\"requirements\":{\"active\":[1]}}", "{\"version\":1,\"requirements\":{\"active\":[\"a\"]},\"ignore\":true}",
    ] {
    try @exportercontract.read_coverage_plan(source) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected strict plan rejection")
    }
  }
  let plan = @exportercontract.read_coverage_plan(
    "{\"version\":1,\"requirements\":{\"active\":[\"startup\"]}}",
  )
  let metric = @exportercontract.Metric::new("active", Gauge, [])
  let declaration = contract([metric])
  let report = @exportercontract.verify_required_sources(
    declaration,
    [@exportercontract.Observation::new("startup", [metric])],
    plan,
  )
  assert_eq(report.report().verdict(), Compatible)
}
