// What the Swift side of the app can see of the C side.
//
// One entry, and it is expected to stay that way: the only C in this project is
// the vendored Zstandard decoder, needed because Claude Desktop's HTTP cache
// stores bodies as zstd and macOS ships no decoder for it. See
// Sources/Vendor/zstd/README.md.
#import "Vendor/zstd/CodenotchZstd.h"
