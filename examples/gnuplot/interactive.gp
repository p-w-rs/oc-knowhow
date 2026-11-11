# Interactive plots: a window you can zoom/rotate (qt), or a standalone HTML page with mouse coordinates and
# zoom (canvas). Run with -e "out='plot.html'" for the HTML page, or out='screen' for a qt window.
if (!exists("out")) out = "interactive.html"
if (out eq "screen") { set terminal qt size 1000,700 enhanced } else { load "_common.gp" }
set xrange [-3:3]; set yrange [-3:3]
set isosamples 50
set palette viridis
set xlabel "x"; set ylabel "y"
splot x*exp(-x**2-y**2) with pm3d title "drag to rotate, right-drag to zoom"
if (out eq "screen") { pause mouse close }
