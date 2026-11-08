# Sources and licenses

Project source and tests are licensed under Apache-2.0. No third-party
implementation or test-suite source is copied into the library or tests.

| Resource | Use | License / source |
| --- | --- | --- |
| `JYPeng487/moonopenmetrics@0.1.1` | Dependency: OpenMetrics parser, validator, label encoding and number parsing | Apache-2.0; [Mooncakes](https://mooncakes.io/docs/JYPeng487/moonopenmetrics) |
| `moonbitlang/async@0.22.5` | Dependency: CLI and end-to-end runner I/O/processes | Apache-2.0; [upstream](https://github.com/moonbitlang/async) |
| MoonBit bundled core | Standard library, JSON and encoding | Apache-2.0; [upstream](https://github.com/moonbitlang/core) |
| Kubernetes stable metric inventory | Unmodified YAML fixture; selected descriptors transcribed into JSON | Apache-2.0; see [exact provenance](fixtures/kubernetes/README.md) |
| OpenMetrics 1.0 specification | Wire-format reference; implementation delegated to dependency | [Upstream specification](https://github.com/prometheus/OpenMetrics/blob/v1.0.0/specification/OpenMetrics.md), Apache-2.0 |
| MoonBit community workflow template | Reference for official installer commands | [Source](https://github.com/moonbit-community/.github/blob/main/workflow-templates/check.yml); no template file copied |
| `actions/checkout@v4`, `ilammy/msvc-dev-cmd@v1` | Hosted CI actions | MIT, [checkout](https://github.com/actions/checkout), [MSVC setup](https://github.com/ilammy/msvc-dev-cmd) |

Dependency versions are declared explicitly in `moon.mod`; dependencies are
downloaded by MoonBit and are not vendored. The upstream Kubernetes data is
kept with its original bytes; derived descriptors and synthetic scrape values
are identified separately. Test cases are project-authored; fixtures are not
presented as captures from a production Kubernetes server.
