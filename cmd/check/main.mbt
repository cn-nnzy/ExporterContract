///|
suberror InputError {
  InputError(String, String)
}

///|
async fn read_text(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly) catch {
    _ => raise InputError("cannot-open", path)
  }
  defer file.close()
  let output = @buffer.Buffer()
  while true {
    let chunk = file.read_some(max_len=65536) catch {
      _ => raise InputError("cannot-read", path)
    }
    match chunk {
      None => break
      Some(bytes) => {
        if output.length() + bytes.length() > 8388608 {
          raise InputError("file-limit-8MiB", path)
        }
        output.write_bytes(bytes)
      }
    }
  }
  @utf8.decode(output.to_bytes(), ignore_bom=true) catch {
    _ => raise InputError("invalid-utf8", path)
  }
}

///|
fn usage() -> String {
  let text =
    #|ExporterContract 0.1.0
    #|  compare BASELINE.json CANDIDATE.json [--json]
    #|  verify CONTRACT.json SCRAPE.om [--json]
    #|  verify-many CONTRACT.json SCRAPE.om [SCRAPE.om ...] [--json]
    #|  draft EXPORTER SCRAPE.om [SCRAPE.om ...]
    #|  review-template BASELINE.json CANDIDATE.json
    #|  assess BASELINE.json CANDIDATE.json REVIEW.json [--json]
    #|  normalize CONTRACT.json
    #|  combine CONTRACT.json [CONTRACT.json ...]
    #|  select CONTRACT.json SCOPE FAMILY [FAMILY ...]
    #|  diff BASELINE.json CANDIDATE.json
    #|  help
    #|Exit codes: 0 compatible, 1 incompatible, 2 invalid input/usage, 3 inconclusive.
    #|Compatibility is scoped to the supplied evidence and stable-v1 policy.
    #|assess: 0 migration ready, 1 needs review, 2 invalid/stale, 3 inconclusive.
    #|draft/normalize/review-template: 0 artifact prepared, 2 invalid input/usage.
    #|
  text
}

///|
async fn read_observations(
  paths : ArrayView[String],
) -> Array[@contract.Observation] {
  if paths.is_empty() || paths.length() > 64 {
    raise InputError("batch-size-1-to-64", "/observations")
  }
  let observations = []
  for path in paths {
    observations.push(@om.read_export(read_text(path), source=path))
  }
  observations
}

///|
fn verdict_code(verdict : @contract.Verdict) -> Int32 {
  match verdict {
    Compatible => 0
    Incompatible => 1
    Inconclusive => 3
  }
}

///|
async fn run(args : Array[String]) -> (String, Int32) {
  let as_json = args.last() == Some("--json")
  let args = if as_json { args[:args.length() - 1].to_owned() } else { args }
  let result = match args {
    ["diff", before, after] if !as_json => {
      let value = @contract.contract_diff(
        @contract.read_contract(read_text(before)),
        @contract.read_contract(read_text(after)),
      )
      return (value.stringify(indent=2) + "\n", 0)
    }
    ["select", path, exporter, .. names] if !as_json => {
      let selected = @contract.select_contract(
        @contract.read_contract(read_text(path)),
        names.to_owned(),
        exporter~,
      )
      return (selected.to_text(), 0)
    }
    ["combine", .. paths] if !as_json => {
      if paths.is_empty() || paths.length() > 64 {
        raise InputError("batch-size-1-to-64", "/contracts")
      }
      let parts = []
      for path in paths {
        parts.push(@contract.read_contract(read_text(path)))
      }
      return (@contract.combine_contracts(parts).to_text(), 0)
    }
    ["review-template", before, after] if !as_json => {
      let value = @contract.migration_template(
        @contract.read_contract(read_text(before)),
        @contract.read_contract(read_text(after)),
      )
      return (value.stringify(indent=2) + "\n", 0)
    }
    ["assess", before, after, review] => {
      let assessment = @contract.assess_migration(
        @contract.read_contract(read_text(before)),
        @contract.read_contract(read_text(after)),
        @contract.read_migration_review(read_text(review)),
      )
      let code = match assessment.status() {
        Ready => 0
        NeedsReview => 1
        Inconclusive => 3
      }
      return (
        if as_json {
          assessment.to_json().stringify(indent=2) + "\n"
        } else {
          assessment.to_text()
        },
        code,
      )
    }
    ["draft", exporter, .. paths] if !as_json => {
      let draft = @contract.draft_contract(exporter, read_observations(paths))
      return (draft.to_text(), 0)
    }
    ["verify-many", declaration, .. paths] => {
      let contract = @contract.read_contract(read_text(declaration))
      let batch = @contract.verify_exports(contract, read_observations(paths))
      return (
        if as_json {
          batch.to_json().stringify(indent=2) + "\n"
        } else {
          batch.to_text()
        },
        verdict_code(batch.report().verdict()),
      )
    }
    ["compare", before, after] => {
      let baseline = @contract.read_contract(read_text(before))
      let candidate = @contract.read_contract(read_text(after))
      @contract.compare_contracts(baseline, candidate)
    }
    ["verify", declaration, scrape] => {
      let contract = @contract.read_contract(read_text(declaration))
      let observation = @om.read_export(read_text(scrape), source=scrape)
      @contract.verify_export(contract, observation)
    }
    ["normalize", path] if !as_json =>
      return (@contract.read_contract(read_text(path)).to_text(), 0)
    ["help"] | [] if !as_json => return (usage(), 0)
    _ => return (usage(), 2)
  }
  let code = verdict_code(result.verdict())
  (
    if as_json {
      result.to_json().stringify(indent=2) + "\n"
    } else {
      result.to_text()
    },
    code,
  )
}

///|
async fn main {
  let (output, code) = run(@env.args()[1:].to_owned()) catch {
    @contract.ContractError(code, path, message) => {
      @stdio.stderr.write(
        ({ "error": code, "location": path, "message": message } : Json).stringify() +
        "\n",
      )
      @env.exit(2)
    }
    @om.ExportError(code, path, message) => {
      @stdio.stderr.write(
        ({ "error": code, "location": path, "message": message } : Json).stringify() +
        "\n",
      )
      @env.exit(2)
    }
    InputError(code, path) => {
      @stdio.stderr.write(
        (
          {
            "error": code,
            "location": path,
            "message": if code == "batch-size-1-to-64" {
              "supply between 1 and 64 scrape paths"
            } else {
              "provide a readable UTF-8 file within the documented size limits"
            },
          } : Json).stringify() +
        "\n",
      )
      @env.exit(2)
    }
    _ => {
      @stdio.stderr.write(
        "{\"error\":\"runtime-io\",\"message\":\"input or output operation failed\"}\n",
      )
      @env.exit(2)
    }
  }
  @stdio.stdout.write(output)
  @env.exit(code)
}
