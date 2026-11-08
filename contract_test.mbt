///|
fn metric(name : String) -> @exportercontract.Metric raise {
  @exportercontract.Metric::new(name, Gauge, ["zone", "method"])
}

///|
test "contract encoding is canonical and round trips" {
  let a = @exportercontract.Contract::new(
    "service",
    [metric("z"), metric("a")],
    complete=true,
  )
  let b = @exportercontract.Contract::new(
    "service",
    [
      @exportercontract.Metric::new("a", Gauge, ["method", "zone"]),
      @exportercontract.Metric::new("z", Gauge, ["method", "zone"]),
    ],
    complete=true,
  )
  assert_eq(a.to_text(), b.to_text())
  assert_eq(@exportercontract.read_contract(a.to_text()), a)
  assert_eq(@exportercontract.read_contract(a.to_text()).to_text(), a.to_text())
}

///|
test "constructors and getters do not leak mutable backing arrays" {
  let labels = ["zone"]
  let buckets = [0.1, 1.0]
  let m = @exportercontract.Metric::new("latency", Histogram, labels, buckets~)
  labels.push("secret")
  buckets[0] = 0.2
  let exposed = m.labels()
  exposed.push("other")
  m.buckets()[0] = 0.5
  assert_eq(m.labels(), ["zone"])
  assert_eq(m.buckets(), [0.1, 1.0])
  let metrics = [m]
  let contract = @exportercontract.Contract::new("api", metrics, complete=true)
  metrics.clear()
  contract.metrics().clear()
  assert_eq(contract.metrics().length(), 1)
}

///|
test "malformed and unsupported JSON is rejected without permissive coercion" {
  let cases = [
    "{}", "{\"version\":2,\"exporter\":\"x\",\"complete\":true,\"metrics\":[]}",
    "{\"version\":1,\"exporter\":\"x\",\"metrics\":[]}", "{\"version\":1,\"exporter\":\"x\",\"complete\":\"true\",\"metrics\":[]}",
    "{\"version\":1,\"exporter\":\"x\",\"complete\":true,\"metrics\":[],\"ignored\":123}",
    "{\"version\":1,\"version\":1,\"exporter\":\"x\",\"complete\":true,\"metrics\":[]}",
    "{\"version\":1,\"ver\\u0073ion\":1,\"exporter\":\"x\",\"complete\":true,\"metrics\":[]}",
    "{\"version\":1,\"exporter\":\"x\",\"complete\":true,\"metrics\":[{\"name\":\"a\",\"kind\":\"gauge\",\"labels\":[]}]}",
    "{\"version\":1,\"exporter\":\"x\",\"complete\":true,\"metrics\":[{\"name\":\"a\",\"kind\":\"summary\",\"labels\":[],\"unit\":null}]}",
    "{\"version\":1,\"exporter\":\"x\",\"complete\":true,\"metrics\":[{\"name\":\"a\",\"kind\":\"gauge\",\"labels\":[],\"unit\":null,\"note\":1}]}",
    "{\"version\":1,\"exporter\":\"x\",\"complete\":true,\"metrics\":[]} trailing",
    "{\"version\":1,",
  ]
  for input in cases {
    try @exportercontract.read_contract(input) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected strict contract rejection")
    }
  }
  // Rejection must not leave state that affects a later valid document.
  let valid = @exportercontract.read_contract(
    "{\"version\":1,\"exporter\":\"ok\",\"complete\":true,\"metrics\":[]}",
  )
  assert_eq(valid.exporter(), "ok")
}

///|
test "invalid descriptors and generated name collisions are rejected" {
  for name in ["", "9bad", "bad name", "bad\nname", "中文"] {
    try @exportercontract.Metric::new(name, Gauge, []) catch {
      @exportercontract.ContractError(code, _, _) =>
        assert_eq(code, "invalid-metric-name")
    } noraise {
      _ => fail("expected invalid name")
    }
  }
  for labels in [["same", "same"], ["__name__"], ["le"], ["quantile"]] {
    try @exportercontract.Metric::new("a", Gauge, labels) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid labels")
    }
  }
  let counter = @exportercontract.Metric::new("requests", Counter, [])
  let gauge = @exportercontract.Metric::new("requests_total", Gauge, [])
  try
    @exportercontract.Contract::new("api", [counter, gauge], complete=true)
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "sample-name-collision")
  } noraise {
    _ => fail("expected sample collision")
  }
  try
    @exportercontract.Contract::new("api", [gauge, gauge], complete=true)
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "duplicate-metric")
  } noraise {
    _ => fail("expected duplicate family")
  }
}

///|
test "histogram bounds have strict finite ordering" {
  for bounds in [[], [1.0, 1.0], [2.0, 1.0], [0.0 / 0.0], [1.0 / 0.0]] {
    try
      @exportercontract.Metric::new("latency", Histogram, [], buckets=bounds)
    catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected invalid histogram")
    }
  }
  let accepted = @exportercontract.Metric::new("temperature", Histogram, [], buckets=[
    -10.0, 0.0, 10.0,
  ])
  assert_eq(accepted.buckets(), [-10.0, 0.0, 10.0])
  try @exportercontract.Metric::new("g", Gauge, [], buckets=[1.0]) catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "unexpected-buckets")
  } noraise {
    _ => fail("expected unsupported buckets")
  }
}

///|
test "contract limits reject oversized and excessively nested inputs" {
  try @exportercontract.read_contract(" ".repeat(2097153)) catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "input-limit")
  } noraise {
    _ => fail("expected size limit")
  }
  try
    @exportercontract.read_contract("[".repeat(33) + "0" + "]".repeat(33))
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "invalid-json")
  } noraise {
    _ => fail("expected depth limit")
  }
}

///|
test "numeric bucket boundaries round trip and signed zero is canonical" {
  let make = fn(bounds : Array[Double]) -> @exportercontract.Contract raise {
    @exportercontract.Contract::new(
      "api",
      [@exportercontract.Metric::new("range", Histogram, [], buckets=bounds)],
      complete=true,
    )
  }
  let bounds = [-1.0e300, -1.0e-300, 0.0, 1.0e-300, 1.0e300]
  let original = make(bounds)
  let decoded = @exportercontract.read_contract(original.to_text())
  assert_eq(decoded, original)
  assert_eq(decoded.metrics()[0].buckets(), bounds)
  assert_eq(make([-0.0, 1.0]).to_text(), make([0.0, 1.0]).to_text())
}

///|
test "descriptor limits include exact boundary values" {
  let accepted = @exportercontract.Metric::new("a".repeat(256), Gauge, [])
  assert_eq(accepted.name().length(), 256)
  try @exportercontract.Metric::new("a".repeat(257), Gauge, []) catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "invalid-metric-name")
  } noraise {
    _ => fail("expected name limit")
  }
  let labels : Array[String] = []
  let bounds : Array[Double] = []
  for i in 0..<256 {
    bounds.push(i.to_double())
  }
  for i in 0..<64 {
    labels.push("label_\{i}")
  }
  let metric = @exportercontract.Metric::new(
    "range",
    Histogram,
    labels,
    buckets=bounds,
  )
  assert_eq(metric.labels().length(), 64)
  assert_eq(metric.buckets().length(), 256)
  labels.push("extra")
  try @exportercontract.Metric::new("range", Gauge, labels) catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "label-limit")
  } noraise {
    _ => fail("expected label limit")
  }
  bounds.push(256.0)
  try
    @exportercontract.Metric::new("range", Histogram, [], buckets=bounds)
  catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "bucket-limit")
  } noraise {
    _ => fail("expected bucket limit")
  }
}
