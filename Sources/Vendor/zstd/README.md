# Vendored Zstandard decoder

`zstddeclib.c` is Zstandard's official single-file **decode-only**
amalgamation. It is here because Claude Desktop's HTTP cache stores response
bodies with `content-encoding: zstd`, and macOS ships no zstd anywhere a signed
app can reach it — not in `Compression.framework` (zlib, LZFSE, LZ4, LZMA,
Brotli, LZBITMAP) and not as a dylib in `/usr/lib`. Linking Homebrew's
`libzstd.dylib` is not an option either: it is absent on users' machines, and a
notarized bundle cannot load a library from `/opt/homebrew`.

Only `Sources/Providers/ClaudeDesktopUsageCache.swift` uses it, through the four
declarations in `CodenotchZstd.h`. Nothing compresses.

## Provenance

| | |
|---|---|
| Upstream | <https://github.com/facebook/zstd> |
| Version | v1.5.7 |
| Release tarball | `zstd-1.5.7.tar.gz`, sha256 `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` |
| Source archive | `v1.5.7.tar.gz`, sha256 `37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3` (the hash Homebrew's `zstd` formula pins, checked as an independent second source; `lib/` is byte-identical between the two tarballs) |
| Licence | BSD-3-Clause — `LICENSE` beside this file. Upstream dual-licences BSD-3-Clause **or** GPLv2; BSD-3-Clause is the option taken. |
| Local edits | none. `zstddeclib.c` is byte-for-byte what the generator below produced. |

## Regenerating

From an unpacked release of the version you want:

```sh
cd build/single_file_libs
python3 ./combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c
```

That is exactly what upstream's own `create_single_file_decoder.sh` runs. Copy
the result over `zstddeclib.c`, copy the release's `LICENSE` over `LICENSE`,
update the table above, and re-check `CodenotchZstd.h` against the release's
`lib/zstd.h`.

`-x legacy/zstd_legacy.h` drops support for frames written by zstd 0.x, which
nothing has produced for a decade. Dropping it, and taking the decoder rather
than the full library, is what keeps this to one file.
