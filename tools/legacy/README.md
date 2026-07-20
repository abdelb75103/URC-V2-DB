# Legacy Utilities

These files are retained for historical reference only. They are not supported production pipeline entrypoints and must not create final, parity, or release artifacts.

`export_filled_standardised.mjs` predates the current export-audit contract: it does not bind its output to a curated build or record an output checksum and pipeline run. If this export is needed again, move the behavior behind the Python CLI and add version-set/build identity, row count, output checksum, destination class, and audit evidence before use.
