///|
fn main raise {
  let report = try {
    let metric = @contract.Metric::new("requests", Counter, ["method", "status"])
    let declaration = @contract.Contract::new(
      "example-http-service",
      [metric],
      complete=true,
    )
    let scrape =
      #|# TYPE requests counter
      #|requests_total{method="GET",status="200"} 42
      #|# EOF
      #|
    let observation = @openmetrics.read_export(
      scrape,
      source="example-integration-test",
    )
    @contract.verify_export(declaration, observation)
  } catch {
    @contract.ContractError(code, path, message) =>
      fail("\{code} at \{path}: \{message}")
    @openmetrics.ExportError(code, path, message) =>
      fail("\{code} at \{path}: \{message}")
    _ => fail("unexpected library error")
  }
  println(report.to_text())
}
