# Shared setup for the examples: output file from `out` (default <script>.png), colorblind-safe colors, clean style.
# Usage: gnuplot -e "out='plot.pdf'" example.gp   (.png .pdf .svg .webp .html select the terminal)
if (!exists("out")) { out = ARG0[1:strlen(ARG0)-3] . ".png" }
ext = out
while (strstrt(ext, ".") > 0) { ext = ext[strstrt(ext, ".")+1:] }   # text after the LAST dot (paths may contain dots)
if (ext eq "png")  { set terminal pngcairo size 1200,800 enhanced font "Helvetica,14" }
if (ext eq "pdf")  { set terminal pdfcairo size 6in,4in enhanced font "Helvetica,10" }
if (ext eq "svg")  { set terminal svg size 1200,800 dynamic enhanced font "Helvetica,14" }
if (ext eq "html") { set terminal canvas size 1000,700 mousing jsdir "https://gnuplot.sourceforge.net/demo_canvas_6.0/" standalone }
set output out
# Okabe-Ito palette (distinguishable with color-vision deficiency)
array OI[8] = ["#0072B2", "#E69F00", "#009E73", "#D55E00", "#CC79A7", "#56B4E9", "#F0E442", "#000000"]
do for [i=1:8] { set linetype i linecolor rgb OI[i] linewidth 2 pointtype 7 pointsize 1 }
set border 3 linewidth 1.2
set tics nomirror out
set grid linetype 0 linecolor rgb "#cccccc"
set key noautotitle
