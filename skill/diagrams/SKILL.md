---
name: diagrams
description: Make clear technical diagrams — architecture and system diagrams, data/ML pipelines, flowcharts and decision trees, sequence diagrams, state machines, ER/class diagrams, graphs and trees, neural-network block diagrams — with D2, Graphviz (dot), Mermaid or TikZ, choosing the right tool, controlling layout, rendering through Pixi (commands that work offline with conda-forge builds) and checking the result visually. Load before drawing any diagram (not data plots: use the gnuplot skill for those).
---

# Diagrams

## Pick the tool

| Need | Tool | Why |
|---|---|---|
| Architecture, systems, containers/nesting, icons, sequence diagrams | **D2** | readable syntax, good automatic layout (ELK/dagre), themes, containers |
| Graphs, trees, dependency/call graphs, generated from data | **Graphviz** (`dot`, `neato`, `fdp`, `sfdp`, `circo`, `twopi`) | best automatic layout for large or generated graphs; trivial to emit from code |
| Diagrams inside Markdown (README, issues, docs sites) | **Mermaid** | GitHub/GitLab render ` ```mermaid ` blocks without image files |
| Papers and LaTeX documents, precise placement, math | **TikZ** | typeset with the document's fonts and math; exact control |
| Full control, unusual graphics, web | hand-written **SVG** | when no layout engine fits |

Rules of thumb: layered flow with < ~30 nodes → D2 or `dot`; > 100 nodes or no natural direction → `sfdp`/`neato`;
must live in a README → Mermaid (keep it small); must match a paper's math and fonts → TikZ.

## Workflow (always)

1. Decide the **one thing the diagram explains** and its audience; leave out everything else (≤ ~15 nodes per
   diagram; split big systems into an overview plus detail diagrams).
2. Start from an example (shipped in the plugin's `examples/diagrams/`: `architecture.d2`, `sequence.d2`,
   `pipeline.dot`, `flow.mmd`, `tikz-graph.tex`, and `d2-png.sh`) or the tool's docs (`library_search field=diagrams`,
   or the docs links in `library_catalog`). Keep the diagram source in the repo next to the document.
3. **Render to PNG and look** (*read the image*). Check: no overlapping labels or lines through text, readable text at
   final size, flow direction obvious (left→right or top→bottom), consistent shapes and colors with a meaning, no
   needless crossings, nothing cut off, no orphan nodes. Fix and re-render; change layout settings before rewriting.
4. Deliver SVG/PDF for documents, PNG for chat/slides; keep sources so diagrams can be regenerated.

## Rendering commands that work (conda-forge via Pixi)

```sh
pixi add d2 graphviz librsvg            # or pixi exec --spec d2 / --spec graphviz for one-offs
# D2 → SVG works offline. d2's own PNG/PDF export downloads Playwright + a browser and often fails (404).
bash d2-png.sh diagram.d2 diagram.png 1600   # SVG with real system fonts, then rsvg-convert → PNG (see below)
dot -c                                   # once after installing graphviz from conda-forge (registers the renderers)
dot -Tsvg graph.dot -o graph.svg; dot -Tpng -Gdpi=150 graph.dot -o graph.png; dot -Tpdf graph.dot -o graph.pdf
pixi exec --spec nodejs=24 -- npx -y @mermaid-js/mermaid-cli -i flow.mmd -o flow.png -s 2 -b white   # ~25 s
pixi exec --spec tectonic -- tectonic -X compile figure.tex             # TikZ standalone → PDF (first run downloads)
pixi exec --spec poppler -- pdftocairo -png -r 200 -singlefile figure.pdf figure   # PDF → figure.png to look at
```

- **D2 SVG → PNG trap**: `rsvg-convert` ignores the WOFF fonts D2 embeds and substitutes a wider font, so edge labels
  run over the gaps D2 cut into lines. `d2-png.sh` passes the system sans-serif TTF (`fc-match`) to
  `d2 --font-regular/--font-italic/--font-bold`, renames the font family in the SVG, then runs `rsvg-convert`. If that
  font is .ttc/.otf (d2 reads only .ttf) it falls back to DejaVu Sans (in the Pixi env via `fonts-conda-ecosystem`, so
  minimal Linux works), Verdana or Arial; `D2_SANS="Font Name"` picks another. Browsers show D2's SVG correctly as is.
- **Mermaid SVG trap**: Mermaid puts labels in `<foreignObject>` HTML, which `rsvg-convert` (and many converters,
  LaTeX, Inkscape-less pipelines) drop: boxes without text. Render PNG/PDF with `mmdc` itself (`-o x.pdf` works).
  The CLI uses Puppeteer's headless Chrome (downloaded once to `~/.cache/puppeteer`); conda-forge `mermaid-cli` has
  no osx-arm64 build.
- Don't run `d2 --watch` (opens a browser and blocks); render once and look.

## D2 essentials

- `direction: right`; config inside the file: `vars: { d2-config: { layout-engine: elk; theme-id: 0 } }` (`d2 layout`
  lists engines: dagre and elk bundled; ELK is better for nested containers and ports; `d2 themes` lists themes).
- Containers `group: Title { a; b }`, edges `a -> b: label`, `a <-> b`, `a -- b`, cross-container `x.a -> y.b`;
  `classes` for consistent styling (`class: svc`); `shape:` `cylinder`, `person`, `queue`, `sequence_diagram`,
  `sql_table`, `class`, `image` (with `icon:`); `style.stroke-dash: 3` for dashed edges.
- Layout control: `label.near: bottom-center` moves container titles away from incoming edges; `grid-rows`/
  `grid-columns` (+ `grid-gap`) for aligned layouts; `near: bottom-right` places a legend container; `--pad 20`,
  `--sketch`, `--theme N` on the command line. `d2 fmt file.d2` formats the source in place.
- Keep labels short; put details in a legend or the caption.

## Graphviz essentials

- `rankdir=LR`, `{rank=same; a; b}` aligns nodes, `cluster_` subgraphs draw boxes around groups,
  `constraint=false` for back edges that should not affect ranking, `nodesep`/`ranksep` for spacing, `newrank=true`
  when `rank=same` must cross clusters, global defaults with `graph [...] node [...] edge [...]`.
- `splines=ortho` gives right-angle edges but cannot place edge labels (warning; use `xlabel`); `splines=true`
  (curved) or `polyline` otherwise. HTML-like labels `label=<<table>…</table>>` with `shape=plain` for record/table
  nodes and ports (`t:p -> a`).
- Large graphs: `sfdp` (or `neato` < ~200 nodes) with `overlap=prism`, `outputorder=edgesfirst`; `shape=point` for
  hundreds of nodes. Generate DOT from code for data-driven graphs; quote IDs with spaces or punctuation.

## Mermaid essentials

`flowchart LR|TD`, `sequenceDiagram`, `classDiagram`, `stateDiagram-v2`, `erDiagram`, `gantt`, `gitGraph`,
`mindmap`, `timeline`. Node shapes `A[box]`, `B{decision}`, `C([stadium])`, `D[(database)]`; edges `-->`,
`-.->` (dotted), `==>` (thick), `-- text -->`; `subgraph Title … end`; `classDef svc fill:#E8F1FB,stroke:#0072B2`
and `class A,B svc`. Quote labels with special characters (`A["f(x) = 1"]`); keep it small (layout degrades with
size); check the version GitHub renders before using `-beta` diagram types.

## TikZ essentials

Standalone class for figures (`\documentclass[tikz,border=4pt]{standalone}`), `positioning` library with
`right=of x` / `node distance=12mm and 16mm`, named styles (`blk/.style={draw, rounded corners, minimum width=20mm}`),
`arrows.meta` (`>={Stealth}`), `calc` and `(a.east |- b)` for aligning to another node's coordinate, `fit` for group
boxes, `matrix` for grids, `graphdrawing` (LuaLaTeX only) for automatic layout. Use the document's fonts; math in
`$…$`. Compile to PDF, convert to PNG and look before including it.

## Design rules

- Consistent visual grammar: one shape per kind of thing, one color per category (colorblind-safe: Okabe–Ito
  `#0072B2 #E69F00 #009E73 #D55E00 #CC79A7`, light fills with darker strokes), edge styles with meaning
  (solid = data, dashed = control/feedback) and a legend when not obvious.
- Direction of reading matches the process; minimize crossings; align siblings; group with containers.
- Label every arrow that isn't obvious; no orphan nodes; no decorative 3D/shadows/gradients; text ≥ the
  document's caption size at final scale.
- Neural-network diagrams: show tensor shapes on edges when they matter, group repeated blocks (×N), distinguish
  parameterized layers from operations.
