# Bundled catalog data

`catalog.sqlite` is a read-only export of public `Tab` and `Article` rows from the local development PostgreSQL container. It contains no user accounts, server favorites, upload records, browser storage, or credentials.

Rebuild it from the already-running development database with:

```sh
cd native-macos
python3 tools/export_catalog.py
```

Pass `--container <name>` or `--output <path>` to select a different local container or output path. The exporter uses one PostgreSQL `REPEATABLE READ, READ ONLY` transaction over `docker exec`/`psql`, then atomically replaces the SQLite file after a successful read.

The schema-2 export contains all public `Tab` fields used by the website: identity and descriptive text, category, difficulty, style, key, tuning, sheet form, BPM, time signature, capo, tuning text, heat, uploader, publish date, format, score/XHE/screenshot paths, tags and creation/update timestamps. It also contains all six `Article` fields. `export_metadata` records the UTC export time, source revision identifiers, row counts, deterministic SHA-256 digests of the exported rows, and local resource-reference check counts.

The current export contains 16,233 catalog tabs and 8 articles. The latest export checked 32,453 score/XHE/screenshot references; none were missing or outside the allowed local paths. `MIMICore.CatalogStore` reads the bundled catalog through a read-only SQLite connection and exposes catalog filtering, sorting, pagination, article queries, and playable-date rankings. Search uses literal substring matching over title and artist; it works for Chinese substrings present in the text but does not provide Chinese tokenization or fuzzy ranking.
