///|
fn main raise {
  let metric = @contract.Metric::new("active", Gauge, [])
  let declaration = @contract.Contract::new("example", [metric], complete=true)
  let startup = @contract.Observation::new("startup-test", [metric])
  let result = @contract.verify_required_sources(declaration, [startup], {
    "active": ["traffic-test"],
  })
  assert_eq(result.report().verdict(), Inconclusive)
  println(result.to_text())
}
