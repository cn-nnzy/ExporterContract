# Development and verification

Use stable MoonBit and resolve dependencies with `moon update`. From the root:

```sh
moon version --all
moon run tools/validate.mbtx
```

The local runner formats, generates interfaces, strictly checks all targets,
tests/builds Wasm, Wasm-GC and JavaScript, executes library examples and runs
the Wasm CLI suite. It does not claim native execution. With a C compiler:

```sh
moon test --target native --deny-warn
moon build --target native --deny-warn
moon run tools/e2e.mbtx native
```

CI performs these checks on Linux, macOS and Windows. Windows native requires
a Visual C++ developer environment, initialized by the workflow. Compilation
alone is not runtime validation.

Review generated interfaces from `moon info --target all`; never edit `.mbti`
files by hand. Include implementation, boundary/error tests, examples and accurate
documentation with each capability. Keep automation in `.mbtx`. Test round trips,
permutations, defensive copies, recovery and preservation of conflicting evidence.
Do not silently project unsupported input into a pass or infer completeness from
samples. Preserve the documented source/reviewer trust boundaries.

External fixtures need source, license and modification records. Preserve the
upstream Kubernetes YAML bytes and provenance. See `THIRD_PARTY.md` and
`fixtures/kubernetes/README.md`. Review `docs/ecosystem.md` before expanding scope;
instrumentation, queries, rule graphs and storage remain outside this project.
