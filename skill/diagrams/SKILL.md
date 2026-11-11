---
name: diagrams
description: Make clear technical diagrams — architecture and system diagrams, data/ML pipelines, flowcharts and decision trees, sequence diagrams, state machines, ER/class diagrams, graphs and trees, neural-network block diagrams — with D2, Graphviz (dot), Mermaid or TikZ, choosing the right tool, rendering through Pixi and checking the result visually. Load before drawing any diagram (not data plots: use the gnuplot skill for those).
---

# Diagrams

## Pick the tool

| Need | Tool | Why |
|---|---|---|
| Architecture, systems, containers/nesting, icons, sequence diagrams | **D2** | readable syntax, good automatic layout (ELK/dagre), themes, containers |
| Graphs, trees, dependency/call graphs, generated from data | **Graphviz** (`dot`, `neato`, `fdp`, `sfdp`, `circo`, `twopi`) | best automatic layout for large or generated graphs; trivial to emit from code |
| Diagrams inside Markdown (README, issues, docs sites) | **Mermaid** | rendered by GitHub/GitLab and many viewers without image files |
| Papers and LaTeX documents, precise placement, math | **TikZ** | typeset with the document's fonts and math; exact control |
| Full control, unusual graphics, web | hand-written **SVG** | when no layout engine fits |

Install through Pixi: `pixi add d2 graphviz` (Mermaid CLI: `pixi add mermaid-cli`, which needs a headless browser;
otherwise rely on the viewer). TikZ: compile with `tectonic` (`pixi add tectonic`) or the user's LaTeX.

## Workflow (always)

1. Decide the **one thing the diagram explains** and its audience; leave out everything else.
2. Start from an example (shipped in the plugin's `examples/diagrams/`: `architecture.d2`, `sequence.d2`,
   `pipeline.dot`, `flow.mmd`, `tikz-graph.tex`) or the tool's docs (`library_search field=diagrams`, or the docs links
   in `library_catalog`). Keep the diagram source in the repo next to the document.
3. **Render and look**: produce PNG (or SVG → PNG) and *read the image*. Check: no overlapping labels or lines through
   titles, readable text at final size, flow direction obvious (left→right or top→bottom), consistent shapes and
   colors with a meaning, nothing cut off. Fix and re-render.
4. Deliver SVG/PDF for documents, PNG for chat/slides; keep sources so diagrams can be regenerated.

## Rendering commands and known quirks

```sh
d2 diagram.d2 diagram.svg                 # SVG works offline; d2 PNG/PDF export downloads a headless browser
rsvg-convert -w 1600 -b white diagram.svg -o diagram.png   # SVG → PNG without a browser (librsvg; pixi add librsvg)
dot -c                                     # once after installing graphviz from conda-forge (registers PNG/SVG/PDF output)
dot -Tsvg graph.dot -o graph.svg; dot -Tpng -Gdpi=150 graph.dot -o graph.png
mmdc -i flow.mmd -o flow.svg               # Mermaid CLI (needs a browser); or preview in a Markdown viewer
tectonic -X compile figure.tex             # TikZ standalone → PDF
```

## D2 essentials

- `direction: right`; layout engine `vars: { d2-config: { layout-engine: elk } }` (better for nested containers).
- Containers `group: Title { a; b }`, edges `a -> b: label`, `a <-> b`, classes for consistent styling, `shape:`
  (`cylinder`, `person`, `queue`, `sequence_diagram`, `sql_table`, `class`), `label.near:` to move container titles
  away from edges, `grid-rows/grid-columns` for aligned layouts, `--theme` and `--sketch` options.
- Keep labels short; put details in a legend or the caption.

## Graphviz essentials

- `rankdir=LR`, `rank=same` groups, `cluster_` subgraphs (boxes around groups), `constraint=false` for back edges
  that should not affect ranking, `splines=ortho|spline`, `nodesep/ranksep` for spacing, record/HTML-like labels
  for tables. Large graphs: `sfdp` with `overlap=prism`. Generate DOT from code for data-driven graphs.

## Mermaid essentials

`flowchart LR|TD`, `sequenceDiagram`, `classDiagram`, `stateDiagram-v2`, `erDiagram`, `gantt`, `gitGraph`,
`mindmap`. Quote labels with special characters; keep it small (Mermaid layout degrades with size).

## TikZ essentials

Standalone class for figures (`\documentclass[tikz,border=4pt]{standalone}`), `positioning` library with `right=of`,
named styles (`blk/.style=…`), `arrows.meta`, `fit` for groups, `matrix` for grids, `graphdrawing` (LuaLaTeX) for
automatic layout. Use the document's fonts; math in `$…$`.

## Design rules

- Consistent visual grammar: one shape per kind of thing, one color per category (colorblind-safe: Okabe–Ito), edge
  styles with meaning (solid = data, dashed = control/feedback) and a legend when not obvious.
- Direction of reading matches the process; minimize crossings; align siblings; group with containers.
- Label every arrow that isn't obvious; no orphan nodes; no decorative 3D/shadows.
- Neural-network diagrams: show tensor shapes on edges when they matter, group repeated blocks (×N), distinguish
  parameterized layers from operations.
