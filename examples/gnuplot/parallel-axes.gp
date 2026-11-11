# Many dimensions at once: parallel coordinates, one line per sample, colored by class.
load "_common.gp"
set print $d
do for [i=1:120] { c=int(rand(0)*3); print sprintf("%g %g %g %g %g %d", c+invnorm(rand(0))*0.5, 2-c+invnorm(rand(0))*0.6, rand(0)*4, c*1.5+invnorm(rand(0))*0.4, invnorm(rand(0)), c+1) }
unset print
set border 0; unset ytics; set xtics ("depth" 1, "width" 2, "dropout" 3, "lr" 4, "noise" 5) nomirror
set for [i=1:5] paxis i tics format "%.1f" right offset -1,0   # labels left of each axis, clear of the lines
set style parallelaxis linewidth 1.5 front
set key outside right title "class"
# One `using` per axis; the extra column on the first one carries the line color.
plot $d using 1:6 with parallelaxes linecolor variable linewidth 0.8 notitle, for [col=2:5] '' using col with parallelaxes notitle, \
     for [c=1:3] keyentry with lines lc c title sprintf("%d", c)
