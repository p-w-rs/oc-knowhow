# 2D scalar field as a heatmap with labeled contour lines (e.g. loss landscape, hyperparameter grid).
load "_common.gp"
f(x,y) = sin(1.3*x)*cos(0.9*y) + 0.15*(x**2 + y**2)/4
set xrange [-3:3]; set yrange [-3:3]
set isosamples 120; set samples 120
set palette viridis
set cblabel "loss"
set xlabel "log10(lr) offset"; set ylabel "log10(wd) offset"
set contour base; set cntrparam levels incremental -1, 0.25, 2
unset surface
set table $contours
splot f(x,y)
unset table
unset contour; set surface
set view map
set size ratio -1
splot f(x,y) with pm3d notitle, $contours with lines linecolor rgb "white" linewidth 1 notitle
