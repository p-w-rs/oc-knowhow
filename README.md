# oc-knowhow

Expert know-how for OpenCode agents, plus a reference library they can search and cite. Skills load only when a
task needs them; nothing changes how OpenCode itself works. macOS and Linux; OpenCode 2.2.6+ and Pixi.

| Area | Skills | What agents get |
|---|---|---|
| Data science | `stats-inference`, `experiment-design`, `datasets`, `field-methods` | Choosing and running analyses the current way (effect sizes with intervals, p-values as evidence not verdicts, resampling, mixed models, multiple comparisons, Bayesian options, what is outdated); ablations and whether model A really beats B (seeds, budgets, paired comparisons, aggregate metrics); building, splitting, auditing and documenting datasets; what differs between fields and their reporting standards. Python through Pixi. |
| Figures and diagrams | `gnuplot`, `diagrams` | gnuplot 6 for 2D/3D, interactive and animated plots and more than three dimensions, with 12 tested example scripts; D2, Graphviz, Mermaid and TikZ for diagrams, with examples. Agents render and look at the result before showing it. |
| Machine learning | `ml-training`, `ml-deploy`, `gpu-kernels` | CUDA/ROCm environments and MLflow; TensorRT 11 and Jetson deployment, custom TensorRT plugins, parallel branches; Triton and CUDA/HIP kernels. |
| Reference library | tools `library_catalog`, `library_search`, `library_read` | Ground truth from books, papers, manuals and standards, with page or section citations and each source's status (current, dated, superseded). |

## The reference library

Everything stays on your computer; nothing is included in the plugin, its releases or exports.

- **Free references**: the plugin lists about 50 freely available sources (statistics, causal inference, ML evaluation,
  dataset documentation, reporting guidelines, measurement uncertainty, visualization, the gnuplot 6 manual and its
  official demo scripts, TikZ). **Settings → Know-how → Download free references** fetches them to your computer and
  indexes them; sources a publisher only offers online are listed as links. See `references.json`.
- **Your own folders**: add folders of PDFs, web pages, Markdown, notebooks or Office files (Settings, or
  `pixi run library add ~/Documents/my-library`). An optional `catalog.json` in the folder describes each file for
  agents:
  ```json
  { "sources": [ { "file": "books/old-stats.pdf", "title": "Old Statistics Text", "year": 1998,
                   "status": "dated", "note": "stepwise selection is outdated", "fields": ["statistics"],
                   "useFor": "classic tests", "skip": false } ] }
  ```
- Sources are converted for agents, not people: running headers and page numbers removed, sections following the
  bookmarks or headings with page ranges, gnuplot's manual split per topic and every demo indexed by what it draws.
  Search combines keywords with meaning-based ranking (the same one-time ~290 MB engine as oc-enhance; shared if
  oc-enhance already downloaded it).
- OpenCode's read permissions apply to your folders.
- Agents get a one-line reminder to check the library before quoting or citing anything (exact wording, numbers,
  syntax), instead of relying on memory.

## Install

Requires [OpenCode](https://opencode.ai) 2.2.6+ (CLI or Desktop) and [Pixi](https://pixi.sh); macOS or Linux.

```sh
git clone https://github.com/p-w-rs/oc-knowhow.git && cd oc-knowhow
pixi run --locked install          # runs the tests, then installs a verified snapshot into your OpenCode config
```

Restart OpenCode (or `/reload`), open **Settings → Know-how**, and click **Download free references**; add your own
folders there too. Agents use the skills when relevant; you can also ask, e.g. "use the stats-inference skill".

```sh
pixi run --locked install-status   # what is installed, and whether its files are intact
pixi run --locked rollback         # back to the previous snapshot
pixi run --locked uninstall        # removes only this plugin's entry; settings and the library index stay
pixi run library status            # the library from a terminal (add, remove, download, sync, search)
```

Updating: `git pull && pixi run --locked install`. Settings and the library index live in `~/.local/share/oc-knowhow`.

## Development

```sh
pixi run --locked test             # type check, unit tests, installer test
pixi run --locked examples         # render every gnuplot and diagram example into .local/examples (then look at them)
pixi run --locked smoke-host       # end to end on the real OpenCode CLI with a scripted model
pixi run --locked setup-search     # meaning-based search engine into .local/search (enables its tests)
```

Skills are written for this plugin (they cite sources rather than copying them). Version facts in the ML skills were
checked against official documentation in November 2026; the skills tell agents to verify versions on the machine.
