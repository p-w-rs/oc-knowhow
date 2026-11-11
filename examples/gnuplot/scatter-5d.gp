# Five variables in one 3D scatter: x, y, z position, color = 4th, point size = 5th (with legends for both).
load "_common.gp"
set print $pts
do for [i=1:300] { x=invnorm(rand(0)); y=invnorm(rand(0)); z=0.6*x-0.4*y+0.3*invnorm(rand(0)); print sprintf("%g %g %g %g %g", x, y, z, x*y, 0.5+abs(z)) }
unset print
set palette viridis
set cblabel "x·y (4th variable)"
set view 62, 30
set xlabel "x"; set ylabel "y"; set zlabel "z" rotate parallel
set ticslevel 0
splot $pts using 1:2:3:($5*0.8):4 with points pointtype 7 pointsize variable linecolor palette notitle, \
      keyentry with points pt 7 ps 0.4 lc black title "|z| small", keyentry with points pt 7 ps 1.6 lc black title "|z| large"
