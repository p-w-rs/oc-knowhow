---
name: gnuplot
description: Make excellent figures with gnuplot 6 — 2D and 3D plots, heatmaps and contours, surfaces with lighting, vector fields, distributions (violin/box/jitter), fits with residuals, small multiples, parallel axes and other ways to show more than three dimensions, voxel/isosurface volumes, animations (rotating 3D, time evolution) and interactive output (zoom/rotate windows, standalone HTML), publication output (PDF, SVG, LaTeX). Includes tested example scripts and a render-and-look loop. Load before making any plot or chart.
---

# Figures with gnuplot

## Workflow (always)

1. **Decide what the figure must show** (one message per figure): comparison, distribution, relationship, trend,
   composition, uncertainty. Pick the chart for that, not the one that is easiest.
2. **Start from a tested example** (below) or a demo found with `library_search` (`field=gnuplot`: the gnuplot 6 manual
   and several hundred official demo scripts are indexed once the user downloads the free references). Never write
   gnuplot from memory when an example exists: syntax changed a lot between 4.x, 5.x and 6.x.
3. **Write a script file** (`figures/<name>.gp`), data from files or inline datablocks; no interactive sessions.
4. **Render and look**: produce a PNG, then *read the image* (the read tool shows images) and check: labels and units,
   legend not covering data, nothing cut off, readable font size, sensible ranges, colors distinguishable, the message
   visible at a glance. Fix and re-render until it is right. Only then produce the final format (PDF/SVG) and show the
   user (e.g. open it in the Review pane).
5. Keep figure scripts in the repo and regenerate them from data (a Pixi task `figures`), never edit images by hand.

Get gnuplot through Pixi: `pixi add gnuplot` in the project, or `pixi exec gnuplot script.gp` for one-offs. Check the
version (`gnuplot --version`; this skill targets 6.0) and the available terminals (`gnuplot -e "set terminal"`).

## Tested examples (copy and adapt)

The plugin ships these in `examples/gnuplot/` (path: the oc-knowhow installation; find it with `library_catalog` or the
skill's file location). Each renders with `gnuplot -e "out='name.png'" name.gp` (`.pdf`, `.svg`, `.html` also work):

| Script | Shows |
|---|---|
| `_common.gp` | output by file extension, Okabe–Ito colorblind-safe colors, clean axes |
| `lines-uncertainty.gp` | mean curves with 95% CI bands (seeds), log x axis |
| `distributions.gp` | violin + box + jittered points per group (kdensity with 1/n weights) |
| `fit-residuals.gp` | nonlinear fit with parameter errors and a residual panel |
| `heatmap-contour.gp` | 2D field as heatmap with contour lines (map view) |
| `surface-3d.gp` | lit 3D surface with base contours |
| `vector-field.gp` | magnitude heatmap with unit-direction arrows |
| `scatter-5d.gp` | 3D scatter with color and size as 4th/5th variables, with legends |
| `parallel-axes.gp` | many dimensions as parallel coordinates colored by class |
| `small-multiples.gp` | one panel per subgroup on shared axes (multiplot layout) |
| `isosurface.gp` | 3D point-cloud density as a voxel isosurface |
| `rotate-3d.gp` | animated rotation (WebP; GIF also) |
| `interactive.gp` | standalone HTML (canvas, mouse) or a qt window you can rotate/zoom |

## Output formats

| Need | Terminal |
|---|---|
| Paper/print | `pdfcairo` (vector) or `cairolatex` (LaTeX typesets the text) or `epscairo` |
| Web, slides, editable | `svg` (`dynamic` size); `pngcairo` at 2× size for raster |
| Animation | `webp animate delay <ms>` or `gif animate delay <1/100 s>`; loop over frames with `do for` |
| Interactive file | `canvas standalone mousing` (HTML + JS); or `svg mouse` |
| Interactive window | `qt` (or `wxt`/`x11`/`aqua`); 3D rotates with the mouse; `pause mouse close` keeps it open in scripts |
| In the terminal | `kittycairo`, `sixelgd`, `dumb` (text) — quick looks only |

Size and fonts for the target: e.g. a one-column paper figure `pdfcairo size 3.5in,2.6in font "Helvetica,8"`.

## Representing more than three dimensions

Use, in order of honesty: **small multiples** (facet by one or two variables), **color** (continuous: perceptually
uniform palette such as `viridis`/`cividis`; categorical: Okabe–Ito), **size** (`pointsize variable`) and **point
type**, **parallel axes** (many numeric variables), **animation** (time or a parameter), **linked views**
(scatterplot-matrix via multiplot). Dimension reduction (PCA, UMAP, t-SNE) for exploration only: say which, show
variance explained or neighborhood caveats, never read distances in UMAP/t-SNE as meaningful.

## gnuplot 6 essentials and traps

- Datablocks `$name << EOD … EOD`; `set print $block` to generate data; `set table $t` to capture computed curves.
- Blocks `if (...) { } else { }`, `do for [i=1:n] { }`, function blocks (`function $f(a) << EOF … EOF`), arrays
  `array A[3] = [...]`. Old-style one-line `if` inside braces is an error in 6.
- `'++'` samples over `urange`/`vrange` (set them; they don't follow x/yrange); `'+'` over `trange`/xrange.
  `set samples`/`set isosamples` control density.
- `smooth kdensity` sums kernels: weight each point by `1/n` for a density. Compute it before restricting xrange.
- 3D: `set pm3d depthorder` (or `depth` for isosurfaces), `lighting primary … specular …`, `set xyplane at <zmin>`
  so the base doesn't float, `set view <rot_x>, <rot_z>, <scale>`. `set hidden3d` for wireframes.
- Voxels: `set vgrid $g size N` *then* `set vxrange/vyrange/vzrange`; `vfill` adds a kernel around data points
  (`VoxelDistance`); `splot $g with isosurface level L`.
- Random data: there is no `set seed`. `rand(0)` starts from fixed default seeds, so a script gives the same numbers
  on every run; `rand(N)` (N > 0) reseeds, `rand(-1)` restores the defaults. `invnorm(rand(0))` gives normal noise.
- Fits: `set fit errorvariables` gives `<param>_err`; start parameters non-zero and of the right magnitude; report
  reduced chi² (`FIT_WSSR/FIT_NDF`) and look at residuals.
- Log axes: `set logscale x 10; set format x "10^{%L}"` (enhanced text). Time axes: `set xdata time; set timefmt …;
  set format x …` (or `timecolumn()`).
- Text: `enhanced` for sub/superscripts; with `cairolatex` write LaTeX in labels. Use `set key` options (`outside`,
  `box opaque`, `title`) so the legend never hides data; `keyentry` for legend-only entries.

## Design rules (from visualization research; cite Wilke, Crameri et al. via library_search)

- Show the data (points/jitter) whenever n is small enough; show uncertainty (CIs, bands, error bars) and say what
  they are (SD vs SE vs CI, n) in the caption.
- No rainbow/jet color maps; colorblind-safe palettes; don't encode with red/green alone.
- Bar charts start at zero; line charts need not. Don't use dual y axes when two panels would do. No 3D bars or pies
  for quantitative comparison (gnuplot can draw them; avoid them).
- Same scale across small multiples unless stated; label units on every axis; legible fonts at final size.
- Order categories meaningfully (by value or natural order), not alphabetically by default.
