///|
test "read and verify real-shaped counter gauge and classic histogram exports" {
  let text =
    #|# TYPE requests counter
    #|requests_total{method="GET"} 2
    #|# TYPE active gauge
    #|active 1
    #|# TYPE latency histogram
    #|latency_bucket{le="0.1"} 1
    #|latency_bucket{le="1"} 2
    #|latency_bucket{le="+Inf"} 2
    #|latency_sum 0.5
    #|latency_count 2
    #|# EOF
    #|
  let expected = @contract.Contract::new(
    "api",
    [
      @contract.Metric::new("requests", Counter, ["method"]),
      @contract.Metric::new("active", Gauge, []),
      @contract.Metric::new("latency", Histogram, [], buckets=[0.1, 1.0]),
    ],
    complete=true,
  )
  let observation = @openmetrics.read_export(text, source="sample.om") catch {
    @openmetrics.ExportError(code, location, message) =>
      fail("\{code} at \{location}: \{message}")
  }
  let report = @contract.verify_export(expected, observation)
  assert_eq(report.verdict(), Compatible)
  assert_eq(report.findings().length(), 0)
}

///|
test "one bad label group cannot be hidden by another valid group" {
  let expected = @contract.Contract::new(
    "api",
    [@contract.Metric::new("active", Gauge, ["route"])],
    complete=true,
  )
  let source = "# TYPE active gauge\nactive{route=\"ok\"} 1\nactive{route=\"secret-route\",user_id=\"SECRET-9283\"} 2\n# EOF\n"
  let observation = @openmetrics.read_export(source, source="input.om") catch {
    @openmetrics.ExportError(code, location, message) =>
      fail("\{code} at \{location}: \{message}")
  }
  let report = @contract.verify_export(expected, observation)
  assert_eq(report.verdict(), Incompatible)
  assert_eq(report.findings()[0].code, "label-added")
  assert_false(report.to_json().stringify().contains("SECRET-9283"))
  assert_false(report.to_text().contains("secret-route"))
}

///|
test "unsupported families and metadata reject the entire input" {
  let inputs = [
    "# TYPE active gauge\nactive 1\n# TYPE build info\nbuild_info{version=\"1\"} 1\n# EOF\n",
    "# TYPE active gauge\nactive 1 123\n# EOF\n", "# TYPE requests counter\nrequests_total 1 # {trace_id=\"secret\"} 1\n# EOF\n",
    "# TYPE requests counter\nrequests_total 1\nrequests_created 1\n# EOF\n", "# TYPE active gauge\nactive{le=\"SECRET\"} 1\n# EOF\n",
  ]
  for input in inputs {
    try @openmetrics.read_export(input, source="invalid.om") catch {
      @openmetrics.ExportError(_, _, _) => ()
    } noraise {
      _ => fail("expected rejection without partial results")
    }
  }
  let empty = @openmetrics.read_export("# EOF\n", source="empty.om")
  assert_eq(empty.source(), "empty.om")
}

///|
test "invalid histogram counts and missing EOF remain explicit failures" {
  for
    input in [
      "# TYPE latency histogram\nlatency_bucket{le=\"1\"} 2\nlatency_bucket{le=\"+Inf\"} 1\nlatency_count 1\n# EOF\n",
      "# TYPE active gauge\nactive 1\n", "# TYPE active gauge\nactive{a=\"bad\\q\"} 1\n# EOF\n",
    ] {
    try @openmetrics.read_export(input, source="invalid.om") catch {
      @openmetrics.ExportError(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid scrape")
    }
  }
}
