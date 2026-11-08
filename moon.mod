name = "cn-nnzy/exportercontract"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/cn-nnzy/ExporterContract"

license = "Apache-2.0"

keywords = [ "prometheus", "openmetrics", "compatibility", "metrics", "ci" ]

description = "Review exporter metric contract changes and verify observed exports before release."

preferred_target = "wasm"

supported_targets = "+wasm+wasm-gc+js+native"

import {
  "JYPeng487/moonopenmetrics@0.1.1",
  "moonbitlang/async@0.22.5",
}
