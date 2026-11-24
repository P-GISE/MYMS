# MediaPipe Vision 1.2.3

Local Swift package using Google's unchanged, checksum-pinned MediaPipeTasksVision, MediaPipeTasksCommon, and MediaPipeTaskGraphs binary archives. URLs/checksums and the upstream privacy manifest come from the official package revision recorded in PROVENANCE.json. The manifest includes only vision-related products instead of downloading text/audio/retrieval/decision libraries.

The official `-all_load` calculator-registration flag and required system libraries/frameworks are retained. `sqlite3` is required by the shared Common archive even though this app uses only the vision API. The package initially downloads its binary dependencies; no camera frame is transmitted and inference does not require networking.

The separate TensorFlowLite Swift product is embedded as a signed dynamic framework so its runtime stays separate from MediaPipe's native runtime. Native iPad XCTest validates both engines in the same process.

See LICENSE for Apache 2.0 terms.
