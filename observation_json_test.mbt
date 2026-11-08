///|
test "descriptor evidence round trips repeated families without changing verdicts" {
  let a = @exportercontract.Metric::new("active", Gauge, [])
  let b = @exportercontract.Metric::new("active", Gauge, ["route"])
  let o = @exportercontract.Observation::new("integration", [a, b, a])
  let decoded = @exportercontract.read_observation(o.to_json().stringify())
  assert_eq(decoded, o)
  assert_eq(
    @exportercontract.verify_export(contract([a]), decoded).to_json(),
    @exportercontract.verify_export(contract([a]), o).to_json(),
  )
  assert_eq(decoded.to_json().stringify(), o.to_json().stringify())
}

///|
test "evidence records reject unsupported metadata and malformed fields then recover" {
  for
    source in [
      "{}", "{\"version\":1,\"version\":1}", "{\"version\":2,\"profile\":\"descriptor-only-v1\",\"source\":\"a\",\"descriptors\":[]}",
      "{\"version\":1,\"profile\":\"full\",\"source\":\"a\",\"descriptors\":[]}",
      "{\"version\":1,\"profile\":\"descriptor-only-v1\",\"source\":\"a\",\"descriptors\":[],\"values\":[]}",
    ] {
    try @exportercontract.read_observation(source) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected strict record refusal")
    }
  }
  let empty = @exportercontract.Observation::new("empty", [])
  assert_eq(
    @exportercontract.read_observation(empty.to_json().stringify()),
    empty,
  )
}
