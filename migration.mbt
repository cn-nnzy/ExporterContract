///|
#derive(Eq, Debug)
pub(all) enum MigrationStatus {
  Ready
  NeedsReview
  Inconclusive
}

///|
pub extend MigrationStatus with Eq::{equal, not_equal}

///|
pub extend MigrationStatus with @debug.Debug::{to_repr}

///|
/// A recorded decision for one exact breaking finding. This is an assertion
/// in a review file, not an authenticated identity or cryptographic signature.
pub struct MigrationApproval {
  code : String
  metric : String
  location : String
  reviewer : String
  reason : String
  reference : String
}

///|
pub struct MigrationReview {
  priv baseline : Contract
  priv candidate : Contract
  priv approvals : Array[MigrationApproval]
}

///|
pub fn MigrationReview::approvals(
  self : MigrationReview,
) -> Array[MigrationApproval] {
  self.approvals.map(x => x)
}

///|
fn approval_json(a : MigrationApproval) -> Json {
  {
    "code": a.code,
    "metric": a.metric,
    "location": a.location,
    "reviewer": a.reviewer,
    "reason": a.reason,
    "reference": a.reference,
  }
}

///|
fn review_json(
  before : Contract,
  after : Contract,
  approvals : Array[Json],
) -> Json {
  {
    "version": 1,
    "policy": "stable-v1",
    "baseline": before.to_json(),
    "candidate": after.to_json(),
    "approvals": Json(approvals),
  }
}

///|
pub fn MigrationReview::to_json(self : MigrationReview) -> Json {
  review_json(self.baseline, self.candidate, self.approvals.map(approval_json))
}

///|
fn decision_key(code : String, metric : String, location : String) -> String {
  Json([code, metric, location]).stringify()
}

///|
/// Generate a review file bound to both entire contract models. Blank
/// reviewer/reason/reference values must be filled, or the entry removed.
///
/// ```mbt check
/// test {
///   let c = @exportercontract.Contract::new("service", [], complete=true)
///   let review = @exportercontract.read_migration_review(
///     @exportercontract.migration_template(c, c).stringify(),
///   )
///   assert_eq(@exportercontract.assess_migration(c, c, review).status(), Ready)
/// }
/// ```
pub fn migration_template(
  before : Contract,
  after : Contract,
) -> Json raise ContractError {
  let result = compare_contracts(before, after)
  let entries = result.findings
    .filter(f => f.severity == Breaking)
    .map(f => {
      (
        {
          "code": f.code,
          "metric": f.metric,
          "location": f.location,
          "reviewer": "",
          "reason": "",
          "reference": "",
        } : Json)
    })
  if entries.length() > 10000 {
    refuse(
      "review-approval-limit", "/approvals", "at most 10000 migration decisions are supported",
    )
  }
  let value = review_json(before, after, entries)
  if value.stringify(indent=2).length() > 2097152 {
    refuse(
      "review-size", "/", "the bound review exceeds 2097152 UTF-16 code units; reduce the reviewed scope",
    )
  }
  value
}

///|
fn review_text(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise ContractError {
  let value = text(required(fields, key, path), path + "/" + key)
  if value.trim().is_empty() || value.length() > 1024 {
    refuse(
      "invalid-review-metadata",
      path + "/" + key,
      "record a nonblank reviewer, migration reason, and tracking reference; each is limited to 1024 code units",
    )
  }
  for i in 0..<value.length() {
    if value[i] < ' ' || value[i] == '\u007f' {
      refuse(
        "invalid-review-metadata",
        path + "/" + key,
        "review metadata must not contain control characters",
      )
    }
  }
  value
}

///|
/// Strictly read migration review format 1. Unknown, duplicate, blanket and
/// non-breaking approvals reject the entire record. No approval authenticates a person.
pub fn read_migration_review(
  source : String,
) -> MigrationReview raise ContractError {
  if source.length() > 2097152 {
    refuse("review-size", "/", "review exceeds 2097152 UTF-16 code units")
  }
  let value = @json.parse(
    source,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
  ) catch {
    _ =>
      raise ContractError(
        "invalid-review-json", "/", "provide complete review JSON with unique keys and at most 32 nesting levels",
      )
  }
  let fields = object(value, "", [
    "version", "policy", "baseline", "candidate", "approvals",
  ])
  match required(fields, "version", "") {
    Number(v, ..) if v == 1.0 => ()
    _ =>
      refuse(
        "unsupported-review-version", "/version", "review format version must be 1",
      )
  }
  if text(required(fields, "policy", ""), "/policy") != "stable-v1" {
    refuse(
      "unsupported-review-policy", "/policy", "review decisions must use stable-v1",
    )
  }
  let baseline = read_contract(required(fields, "baseline", "").stringify())
  let candidate = read_contract(required(fields, "candidate", "").stringify())
  let compatibility = compare_contracts(baseline, candidate)
  let known : Map[String, Unit] = Map([])
  for f in compatibility.findings {
    if f.severity == Breaking {
      known[decision_key(f.code, f.metric, f.location)] = ()
    }
  }
  let entries = match required(fields, "approvals", "") {
    Array(entries) => entries
    _ =>
      raise ContractError(
        "expected-array", "/approvals", "provide an array of individual migration decisions",
      )
  }
  if entries.length() > 10000 {
    refuse(
      "review-approval-limit", "/approvals", "at most 10000 migration decisions are supported",
    )
  }
  let seen : Map[String, Unit] = Map([])
  let approvals = entries.mapi((i, entry) => {
    let path = "/approvals/\{i}"
    let fields = object(entry, path, [
      "code", "metric", "location", "reviewer", "reason", "reference",
    ])
    let code = text(required(fields, "code", path), path + "/code")
    let metric = text(required(fields, "metric", path), path + "/metric")
    let location = text(required(fields, "location", path), path + "/location")
    let key = decision_key(code, metric, location)
    if !known.contains(key) {
      refuse(
        "unknown-migration-decision", path, "approval must identify one exact breaking finding for the bound contracts",
      )
    }
    if seen.contains(key) {
      refuse(
        "duplicate-migration-decision", path, "each breaking finding may be approved only once",
      )
    }
    seen[key] = ()
    {
      code,
      metric,
      location,
      reviewer: review_text(fields, "reviewer", path),
      reason: review_text(fields, "reason", path),
      reference: review_text(fields, "reference", path),
    }
  })
  approvals.sort_by((a, b) => {
    lexical(
      decision_key(a.code, a.metric, a.location),
      decision_key(b.code, b.metric, b.location),
    )
  })
  { baseline, candidate, approvals, }
}

///|
pub struct MigrationAssessment {
  priv compatibility : Report
  priv status : MigrationStatus
  priv approvals : Array[MigrationApproval]
  priv outstanding : Array[Finding]
}

///|
pub fn MigrationAssessment::status(
  self : MigrationAssessment,
) -> MigrationStatus {
  self.status
}

///|
pub fn MigrationAssessment::report(self : MigrationAssessment) -> Report {
  self.compatibility
}

///|
pub fn MigrationAssessment::outstanding(
  self : MigrationAssessment,
) -> Array[Finding] {
  self.outstanding.map(x => x)
}

///|
fn migration_status_name(status : MigrationStatus) -> String {
  match status {
    Ready => "ready"
    NeedsReview => "needs-review"
    Inconclusive => "inconclusive"
  }
}

///|
pub fn MigrationAssessment::to_json(self : MigrationAssessment) -> Json {
  {
    "version": 1,
    "policy": "stable-v1",
    "review_status": migration_status_name(self.status),
    "compatibility": self.compatibility.to_json(),
    "approvals": Json(self.approvals.map(approval_json)),
    "outstanding": Json(
      self.outstanding.map(f => {
        ({ "code": f.code, "metric": f.metric, "location": f.location } : Json)
      }),
    ),
  }
}

///|
pub fn MigrationAssessment::to_text(self : MigrationAssessment) -> String {
  "migration review: \{migration_status_name(self.status)}; recorded approvals: \{self.approvals.length()}; outstanding: \{self.outstanding.length()}\n" +
  self.compatibility.to_text()
}

///|
/// Apply recorded migration decisions only to these exact contract models.
/// A ready migration does not change the underlying compatibility verdict.
/// Unknown evidence cannot be approved away.
pub fn assess_migration(
  before : Contract,
  after : Contract,
  review : MigrationReview,
) -> MigrationAssessment raise ContractError {
  if before != review.baseline || after != review.candidate {
    refuse(
      "stale-migration-review", "/", "contracts differ from the reviewed models; regenerate and review the migration record",
    )
  }
  let compatibility = compare_contracts(before, after)
  let accepted : Map[String, Unit] = Map([])
  for approval in review.approvals {
    accepted[decision_key(approval.code, approval.metric, approval.location)] = ()
  }
  let outstanding = compatibility.findings.filter(f => {
    f.severity == Breaking &&
    !accepted.contains(decision_key(f.code, f.metric, f.location))
  })
  let status = if !outstanding.is_empty() {
    NeedsReview
  } else if compatibility.findings.any(f => f.severity == Unknown) {
    Inconclusive
  } else {
    Ready
  }
  { compatibility, status, approvals: review.approvals, outstanding, }
}
