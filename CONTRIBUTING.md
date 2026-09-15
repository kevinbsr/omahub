# Contributing

Keep changes focused and preserve the Hub's theme-driven geometry and
keyboard navigation. New pages should follow the tab contract documented in
the README and avoid polling while hidden.

Run the checks before opening a pull request:

```bash
node --test tests/*.test.cjs
python3 -B -m unittest discover -s tests -p 'test_*.py'
python3 -m json.tool manifest.json >/dev/null
```

For shell testing, link the checkout into the local plugin directory and
restart the shell if the file watcher becomes stale:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/kevin.hub
omarchy restart shell
```

When updating vendored code, retain its copyright notice, record the upstream
revision and describe local modifications in `kdeconnect/VENDORED.md` or the
source file header.
