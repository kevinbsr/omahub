# Contributing

Keep changes focused and preserve the Hub's theme-driven geometry and
keyboard navigation. New pages should follow the tab contract documented in
the README and avoid polling while hidden.

Run the checks before opening a pull request:

```bash
node --test tests/*.test.cjs
python3 -B -m unittest discover -s tests -p 'test_*.py'
python3 -m json.tool manifest.json >/dev/null
tools/vendor-sync verify
```

For shell testing, link the checkout into the local plugin directory and
restart the shell if the file watcher becomes stale:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/kevinbsr.omahub
omarchy restart shell
```

## Vendored code

Two different things here are called vendored, and they have different rules.

**Engines under `vendor/`** are upstream's own code, running unchanged. Never
edit a file there by hand: the tree is derived from `upstream@commit` plus the
patches in `vendor/patches/`, and `tools/vendor-sync verify` rebuilds it and
fails on any difference. A local change goes in a patch, with a header saying
what it does, why, and when it can be deleted. Repin with
`tools/vendor-sync update <engine>`; see `vendor/README.md`.

**Views adapted from upstream** — `kdeconnect/`, `android-mirror/`, and the
`*Model.js` files — are this repo's own code, written against upstream's
behaviour. Retain the copyright notice, and record the upstream revision and
the local modifications in `kdeconnect/VENDORED.md`, `android-mirror/VENDORED.md`,
or the source file header.
