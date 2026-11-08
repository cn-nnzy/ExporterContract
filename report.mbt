///|
#derive(Debug, Eq)
pub(all) enum Severity {
  Notice
  Unknown
  Breaking
}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
#derive(Debug, Eq)
pub(all) enum Verdict {
  Compatible
  Inconclusive
  Incompatible
}

///|
pub extend Verdict with Eq::{equal, not_equal}

///|
pub extend Verdict with @debug.Debug::{to_repr}

///|
#derive(Debug, Eq)
pub struct Finding {
  severity : Severity
  code : String
  metric : String
  location : String
  message : String
  remedy : String
}

///|
pub extend Finding with Eq::{equal, not_equal}

///|
pub extend Finding with @debug.Debug::{to_repr}

///|
#derive(Debug, Eq)
pub struct Report {
  priv scope : String
  priv findings : Array[Finding]
  priv verdict : Verdict
}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub extend Report with @debug.Debug::{to_repr}

///|
fn report(scope : String, findings : Array[Finding]) -> Report {
  let mut verdict = Compatible
  for finding in findings {
    if finding.severity == Breaking {
      verdict = Incompatible
    } else if finding.severity == Unknown && verdict == Compatible {
      verdict = Inconclusive
    }
  }
  findings.sort_by((a, b) => {
    let metric = lexical(a.metric, b.metric)
    if metric != 0 {
      metric
    } else {
      let code = lexical(a.code, b.code)
      if code != 0 {
        code
      } else {
        lexical(a.location, b.location)
      }
    }
  })
  { scope, findings, verdict, }
}

///|
pub fn Report::verdict(self : Report) -> Verdict {
  self.verdict
}

///|
pub fn Report::findings(self : Report) -> Array[Finding] {
  self.findings.map(x => x)
}

///|
pub fn Report::scope(self : Report) -> String {
  self.scope
}

///|
fn severity_name(value : Severity) -> String {
  match value {
    Notice => "notice"
    Unknown => "unknown"
    Breaking => "breaking"
  }
}

///|
fn verdict_name(value : Verdict) -> String {
  match value {
    Compatible => "compatible"
    Inconclusive => "inconclusive"
    Incompatible => "incompatible"
  }
}

///|
/// Stable JSON report format, version 1. No observed label values are included.
pub fn Report::to_json(self : Report) -> Json {
  {
    "version": 1,
    "policy": "stable-v1",
    "scope": self.scope,
    "verdict": verdict_name(self.verdict),
    "findings": self.findings.map(f => {
      (
        {
          "severity": severity_name(f.severity),
          "code": f.code,
          "metric": f.metric,
          "location": f.location,
          "message": f.message,
          "remedy": f.remedy,
        } : Json)
    }),
  }
}

///|
pub fn Report::to_text(self : Report) -> String {
  let output = StringBuilder()
  output.write_string(
    "\{verdict_name(self.verdict)} [\{self.scope}; stable-v1]\n",
  )
  for finding in self.findings {
    output.write_string(
      "\{severity_name(finding.severity)} \{finding.code} \{finding.metric} @ \{finding.location}: \{finding.message}\n  action: \{finding.remedy}\n",
    )
  }
  output.to_string()
}
