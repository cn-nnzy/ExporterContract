///|
fn migration_pair(
  complete~ : Bool = true,
) -> (@exportercontract.Contract, @exportercontract.Contract) raise {
  (
    contract([@exportercontract.Metric::new("active", Gauge, ["route"])]),
    contract([@exportercontract.Metric::new("active", Gauge, [])], complete~),
  )
}

///|
fn fields_of(value : Json) -> Map[String, Json] raise {
  guard value is Object(fields) else { fail("expected test object") }
  fields
}

///|
fn filled_review(
  before : @exportercontract.Contract,
  after : @exportercontract.Contract,
) -> Json raise {
  let value = @exportercontract.migration_template(before, after)
  let fields = fields_of(value)
  guard fields["approvals"] is Array(entries) else {
    fail("expected approvals")
  }
  for entry in entries {
    let approval = fields_of(entry)
    approval["reviewer"] = Json::string("test-reviewer")
    approval["reason"] = Json::string("synthetic consumers have migrated")
    approval["reference"] = Json::string("DEMO-1")
  }
  value
}

///|
fn reject_review(value : Json, code : String) -> Unit raise {
  try @exportercontract.read_migration_review(value.stringify()) catch {
    @exportercontract.ContractError(actual, _, _) => assert_eq(actual, code)
  } noraise {
    _ => fail("expected review rejection")
  }
}

///|
test "approved migration retains the original incompatible verdict" {
  let (before, after) = migration_pair()
  let source = filled_review(before, after).stringify()
  let review = @exportercontract.read_migration_review(source)
  let assessed = @exportercontract.assess_migration(before, after, review)
  assert_eq(assessed.status(), Ready)
  assert_eq(assessed.report().verdict(), Incompatible)
  assert_eq(
    assessed.report().to_json(),
    @exportercontract.compare_contracts(before, after).to_json(),
  )
  assert_eq(assessed.outstanding().length(), 0)
  assert_eq(review.approvals()[0].reviewer, "test-reviewer")
  let again = @exportercontract.read_migration_review(
    review.to_json().stringify(),
  )
  assert_eq(again.to_json(), review.to_json())
  review.approvals().clear()
  assessed.outstanding().clear()
  assert_eq(review.approvals().length(), 1)
}

///|
test "missing and partial decisions leave exact outstanding findings" {
  let before = contract([
    @exportercontract.Metric::new("active", Gauge, ["route"]),
  ])
  let after = contract([
    @exportercontract.Metric::new("active", Gauge, ["method"]),
  ])
  let value = filled_review(before, after)
  let fields = fields_of(value)
  guard fields["approvals"] is Array(entries) else { fail("expected entries") }
  fields["approvals"] = Json([entries[0]])
  let review = @exportercontract.read_migration_review(value.stringify())
  let partial = @exportercontract.assess_migration(before, after, review)
  assert_eq(partial.status(), NeedsReview)
  assert_eq(partial.outstanding().length(), 1)
  partial.outstanding().clear()
  assert_eq(partial.outstanding().length(), 1)
  fields["approvals"] = Json(([] : Array[Json]))
  let empty = @exportercontract.read_migration_review(value.stringify())
  assert_eq(
    @exportercontract.assess_migration(before, after, empty)
    .outstanding()
    .length(),
    2,
  )
}

///|
test "unknown evidence cannot be approved away" {
  let (before, after) = migration_pair(complete=false)
  let review = @exportercontract.read_migration_review(
    filled_review(before, after).stringify(),
  )
  let result = @exportercontract.assess_migration(before, after, review)
  assert_eq(result.outstanding().length(), 0)
  assert_eq(result.status(), Inconclusive)
  assert_true(
    result.report().findings().any(f => f.code == "inventory-incomplete"),
  )
  let value = filled_review(before, after)
  let fields = fields_of(value)
  guard fields["approvals"] is Array(entries) else { fail("expected entries") }
  fields_of(entries[0])["code"] = Json::string("inventory-incomplete")
  reject_review(value, "unknown-migration-decision")
}

///|
test "review bindings reject any model change even when finding IDs repeat" {
  let (before, after) = migration_pair()
  let review = @exportercontract.read_migration_review(
    filled_review(before, after).stringify(),
  )
  let changed = contract([
    @exportercontract.Metric::new("active", Gauge, []),
    @exportercontract.Metric::new("new_family", Gauge, []),
  ])
  try @exportercontract.assess_migration(before, changed, review) catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "stale-migration-review")
  } noraise {
    _ => fail("expected stale binding")
  }
  let old_changed = contract([
    @exportercontract.Metric::new("active", Gauge, ["route"], unit="seconds"),
  ])
  try @exportercontract.assess_migration(old_changed, after, review) catch {
    @exportercontract.ContractError(code, _, _) =>
      assert_eq(code, "stale-migration-review")
  } noraise {
    _ => fail("expected stale baseline")
  }
  let reordered = @exportercontract.read_contract(before.to_text())
  assert_eq(
    @exportercontract.assess_migration(reordered, after, review).status(),
    Ready,
  )
}

///|
test "blank metadata blanket approvals duplicates and unknown fields refuse review" {
  let (before, after) = migration_pair()
  reject_review(
    @exportercontract.migration_template(before, after),
    "invalid-review-metadata",
  )
  for key in ["reviewer", "reason", "reference"] {
    for text in [" ", "x".repeat(1025), "control\ncharacter"] {
      let value = filled_review(before, after)
      let fields = fields_of(value)
      guard fields["approvals"] is Array(entries) else {
        fail("expected entries")
      }
      fields_of(entries[0])[key] = Json::string(text)
      reject_review(value, "invalid-review-metadata")
    }
  }
  for key in ["code", "metric", "location"] {
    let value = filled_review(before, after)
    let fields = fields_of(value)
    guard fields["approvals"] is Array(entries) else {
      fail("expected entries")
    }
    fields_of(entries[0])[key] = Json::string("*")
    reject_review(value, "unknown-migration-decision")
  }
  let duplicate = filled_review(before, after)
  let fields = fields_of(duplicate)
  guard fields["approvals"] is Array(entries) else { fail("expected entries") }
  entries.push(entries[0])
  reject_review(duplicate, "duplicate-migration-decision")
  let unknown = filled_review(before, after)
  fields_of(unknown)["allow_all"] = Json::boolean(true)
  reject_review(unknown, "unknown-field")
  let nested = filled_review(before, after)
  guard fields_of(nested)["approvals"] is Array(items) else {
    fail("expected entries")
  }
  fields_of(items[0])["expires"] = Json::number(0)
  reject_review(nested, "unknown-field")
}

///|
test "review parser rejects malformed versions policies and duplicate escaped keys then recovers" {
  for
    source in ["{", "{\"version\":1,\"ver\\u0073ion\":1}", " ".repeat(2097153)] {
    try @exportercontract.read_migration_review(source) catch {
      @exportercontract.ContractError(_, _, _) => ()
    } noraise {
      _ => fail("expected strict review rejection")
    }
  }
  let (before, after) = migration_pair()
  let version = filled_review(before, after)
  fields_of(version)["version"] = Json::number(2)
  reject_review(version, "unsupported-review-version")
  let policy = filled_review(before, after)
  fields_of(policy)["policy"] = Json::string("permissive")
  reject_review(policy, "unsupported-review-policy")
  let c = contract([])
  let valid = @exportercontract.read_migration_review(
    @exportercontract.migration_template(c, c).stringify(),
  )
  assert_eq(@exportercontract.assess_migration(c, c, valid).status(), Ready)
}

///|
test "approval ordering cannot change canonical review or assessment" {
  let before = contract([
    @exportercontract.Metric::new("active", Gauge, ["route"]),
  ])
  let after = contract([
    @exportercontract.Metric::new("active", Gauge, ["method"]),
  ])
  let value = filled_review(before, after)
  let fields = fields_of(value)
  guard fields["approvals"] is Array(entries) else { fail("expected entries") }
  let a = @exportercontract.read_migration_review(value.stringify())
  fields["approvals"] = Json([entries[1], entries[0]])
  let b = @exportercontract.read_migration_review(value.stringify())
  assert_eq(a.to_json(), b.to_json())
  assert_eq(
    @exportercontract.assess_migration(before, after, a).to_json(),
    @exportercontract.assess_migration(before, after, b).to_json(),
  )
}
