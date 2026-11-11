---
name: gnuplot
description: Make excellent figures with gnuplot 6 — 2D and 3D plots, heatmaps and contours, correlation matrices, surfaces with lighting, vector fields, distributions (violin/box/jitter), bars and dot plots with error bars/CIs, fits with residuals, small multiples, log axes, parallel axes and other ways to show more than three dimensions, voxel/isosurface volumes, colorblind-safe palettes (viridis, cividis, batlow), animations (rotating 3D, time evolution) and interactive output (zoom/rotate windows, standalone HTML), publication output (PDF, SVG, LaTeX) at the right size. Includes tested example scripts and a render-and-look loop. Load before making any plot or chart.
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
   legend not covering data, nothing cut off (violin/density tails, long tick labels), readable font size, sensible
   ranges, colors distinguishable, the message visible at a glance. Fix and re-render until it is right. Only then
   produce the final format (PDF/SVG) and show the user (e.g. open it in the Review pane).
5. Keep figure scripts in the repo and regenerate them from data (a Pixi task `figures`), never edit images by hand.

Get gnuplot through Pixi: `pixi add gnuplot` in the project, or `pixi exec gnuplot script.gp` for one-offs. Check the
version (`gnuplot --version`; this skill targets 6.0) and the terminals (`gnuplot -e "set terminal"`). The conda-forge
build has `pngcairo pdfcairo epscairo svg cairolatex epslatex canvas webp gif qt kittycairo sixelgd dumb`, but no
`wxt`, `aqua`, `x11` or `tikz`/`lua`. Help without a pager: `PAGER=cat gnuplot -e "help set palette"`.

## Tested examples (copy and adapt)

The plugin ships these in `examples/gnuplot/` (path: the oc-knowhow installation; find it with `library_catalog` or the
skill's file location). Each renders with `gnuplot -e "out='name.png'" name.gp` (`.pdf`, `.svg`, `.html` also work):

| Script | Shows |
|---|---|
| `_common.gp` | output by file extension, Okabe–Ito colorblind-safe colors, clean axes |
| `_palettes.gp` | `batlow`, `cividis` (sequential) and `vik` (diverging) for `set palette defined @batlow` |
| `lines-uncertainty.gp` | mean curves with 95% CI bands (seeds), log x axis |
| `bars-errorbars.gp` | clustered bars from zero with CI error bars, and the dot + interval alternative |
| `distributions.gp` | violin + box + jittered points per group (kdensity with 1/n weights, tails not cut) |
| `fit-residuals.gp` | nonlinear fit with parameter errors and a residual panel |
| `heatmap-contour.gp` | 2D field as heatmap with contour lines (map view) |
| `correlation-matrix.gp` | signed matrix, diverging palette centred on 0, values printed in cells |
| `surface-3d.gp` | lit 3D surface with base contours |
| `vector-field.gp` | magnitude heatmap with unit-direction arrows |
| `scatter-5d.gp` | 3D scatter with color and size as 4th/5th variables, with legends |
| `parallel-axes.gp` | many dimensions as parallel coordinates colored by class |
| `small-multiples.gp` | one panel per subgroup on shared axes (multiplot layout) |
| `isosurface.gp` | 3D point-cloud density as a voxel isosurface |
| `rotate-3d.gp` | animated rotation (WebP; GIF also) |
| `interactive.gp` | standalone HTML (canvas, mouse) or a qt window you can rotate/zoom |

## Output formats and sizes

| Need | Terminal |
|---|---|
| Paper/print | `pdfcairo` (vector); `cairolatex pdf` (LaTeX typesets the text, matches the paper's fonts); `epscairo` |
| Web, slides, editable | `svg` (`dynamic` size); `pngcairo` at 2× the display size for raster |
| Animation | `webp animate delay <ms>` or `gif animate delay <1/100 s>`; loop over frames with `do for` |
| Interactive file | `canvas standalone mousing` (HTML + JS; zoom with right-drag); or `svg mouse standalone` |
| Interactive window | `qt` (3D rotates with the mouse); `pause mouse close` keeps it open in scripts |
| In the terminal | `kittycairo`, `sixelgd`, `dumb` (text) — quick looks only |

- **Size the figure at its final size**, then choose fonts for that size; never scale a big figure down. One column
  ≈ 3.3–3.5 in, two columns ≈ 7 in (check the venue): `set terminal pdfcairo size 3.5in,2.6in font "Helvetica,8"`.
  Text in the figure ≈ the caption size (7–9 pt in print); lines ≥ 1 pt (`linewidth 1.5` at this size).
- `cairolatex pdf standalone` writes `x.tex` + `x-inc.pdf`; compile with `tectonic x.tex` (`pixi exec --spec tectonic`)
  to check the look. Without `standalone`, `\input{x.tex}` it in the paper. Labels are LaTeX (`'$\alpha$ (rad)'`, single
  quotes so backslashes survive); don't use `enhanced` markup there.
- PNG for slides/chat: `pngcairo size 1600,1000 font "Helvetica,20"` (big text; slides are seen from afar).

## Representing more than three dimensions

Use, in order of honesty: **small multiples** (facet by one or two variables), **color** (continuous: perceptually
uniform palette; categorical: Okabe–Ito), **size** (`pointsize variable`) and **point type**, **parallel axes** (many
numeric variables), **animation** (time or a parameter), **linked views** (scatterplot matrix via multiplot).
Dimension reduction (PCA, UMAP, t-SNE) for exploration only: say which, show variance explained or neighborhood
caveats, never read distances in UMAP/t-SNE as meaningful.

## gnuplot 6 essentials and traps

- Datablocks `$name << EOD … EOD`; `set print $block` to generate data; `set table $t` to capture computed curves.
- Blocks `if (...) { } else { }`, `do for [i=1:n] { }`, function blocks (`function $f(a) << EOF … local b = … return b
  EOF`, call `$f(3)`), arrays `array A[3] = [1, "two", 3.5]`, `|A|` is the size. Old-style one-line `if (c) cmd`
  inside braces is an error in 6.
- `'++'` samples over `urange`/`vrange` (default −5..5; set them, they don't follow x/yrange); `'+'` over `trange` if
  set, else xrange, or a sampling range: `plot sample [t=0:2*pi] '+' using (cos(t)):(sin(t))`.
  `set samples`/`set isosamples` control density.
- `smooth kdensity` samples over the *current* x range; autoscaled, that is data min..max, which cuts the tails off.
  Set the range to data ± 3 bandwidths (`stats` gives `STATS_min/max`), weight points by `1/n` for a density.
- Error bars: `with yerrorbars` (`x:y:dy` or `x:y:lo:hi`), `xerrorbars`, `xyerrorbars`; bars with CIs:
  `set style histogram errorbars` + `using mean:lo:hi:xtic(1)`; bands: `with filledcurves` (`x:lo:hi`) under
  `set style fill transparent solid 0.2`. Say what the bars are (SD, SE, 95% CI, n) in the caption or key title.
- Log axes: `set logscale x 10; set format x "10^{%L}"` (enhanced text); `set mxtics 10` for minor ticks. Zero and
  negative values are dropped silently on log axes. Time axes: `set xdata time; set timefmt "%Y-%m-%d";
  set format x "%b %d"` (or `timecolumn(1, "%Y-%m-%d")` in `using`).
- Multiplot: `set multiplot layout r,c margins l,r,b,t spacing sx,sy` gives aligned panels; set shared ranges *before*
  the loop; drop repeated axis labels; `set label "(a)" at graph -0.15, graph 1.05` for panel letters.
- Palettes: named only `viridis` and `cubehelix` (`set palette cividis` is an error): others with
  `set palette defined (0 "#…", 1 "#…")` or `set palette file`; `negative` reverses; `set colormap new NAME` saves
  one for a second palette in the same plot (`fillcolor palette NAME`). Diverging data: symmetric `cbrange`.
- 3D: `set pm3d depthorder` (needed for surfaces and isosurfaces), `lighting primary … specular …`, `set xyplane at
  <zmin>` so the base doesn't float, `set view <rot_x>, <rot_z>, <scale>`, `set view map` for 2D. `set hidden3d` for
  wireframes.
- Voxels: `set vgrid $g size N` *then* `set vxrange/vyrange/vzrange`; `vfill` adds a kernel around data points
  (`VoxelDistance`); `splot $g with isosurface level L`.
- Random data: there is no `set seed`. `rand(0)` starts from fixed default seeds, so a script gives the same numbers
  on every run; `rand(N)` (N > 0) reseeds, `rand(-1)` restores the defaults. `invnorm(rand(0))` gives normal noise.
- Fits: `set fit quiet errorvariables` gives `<param>_err` (`covariancevariables`: `FIT_COV_a_b`); start parameters
  non-zero and of the right magnitude; report reduced chi² (`FIT_WSSR/FIT_NDF`) and look at residuals. With
  `yerror` weights, parameter errors are scaled by the reduced chi² by default (`set fit noerrorscaling` to use
  the given errors as they are) — say which.
- Text: `enhanced` for sub/superscripts (`x_{i}`, `10^{3}`, `{/Symbol a}` or UTF-8 `α`). Legend: `set key` options
  (`outside`, `box opaque`, `title`, `horizontal`) so it never hides data; `keyentry` for legend-only entries.

## Design rules (sources: Wilke, *Fundamentals of Data Visualization*; Crameri et al. 2020 — via library_search)

- Show the data (points/jitter) whenever n is small enough; show uncertainty (CIs, bands, error bars) and say what
  they are (SD vs SE vs CI, n): SD describes the spread of observations, SE/CI the precision of the mean (Wilke ch. 16).
- Color maps must be perceptually uniform and ordered: no rainbow/jet (they invent edges and hide gradients) — use
  viridis, cividis, batlow; diverging (vik) only when there is a meaningful centre. Check readability for
  colour-vision deficiency and in grey; don't encode with red vs green alone (Crameri et al. 2020; Wilke ch. 19).
- Bars on a linear scale start at zero (proportional ink, Wilke ch. 17); dots/lines need not. Don't use dual y
  axes when two panels would do. No 3D bars or pies for quantitative comparison.
- Same scale across small multiples unless stated; label units on every axis; legible fonts at final size.
- Order categories meaningfully (by value or natural order), not alphabetically by default.
- Direct labels beat legends when there are few lines; keep the legend in the order of the lines at the right end.
