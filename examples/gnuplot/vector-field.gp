# Vector field (e.g. gradient flow): magnitude as a heatmap underneath, unit-length arrows on top showing direction.
# Normalizing arrow length keeps small vectors visible; the heatmap carries the magnitude.
load "_common.gp"
set xrange [-2:2]; set yrange [-2:2]; set size ratio -1
set urange [-2:2]; set vrange [-2:2]   # the sampling range of the special file "++" (it does not follow x/yrange)
u(x,y) = -y - 0.3*x*(x**2+y**2-1)
v(x,y) =  x - 0.3*y*(x**2+y**2-1)
m(x,y) = sqrt(u(x,y)**2 + v(x,y)**2)
set palette viridis
set cblabel "|v|"
set style arrow 1 head filled size 0.05,20 linewidth 1.4 linecolor rgb "white"
set samples 200, 200; set isosamples 200, 200
set table $heat
splot '++' using 1:2:(m($1,$2))
unset table
set samples 17, 17; set isosamples 17, 17
plot $heat using 1:2:3 with image notitle, \
     '++' using 1:2:(0.11*u($1,$2)/(m($1,$2)+1e-9)):(0.11*v($1,$2)/(m($1,$2)+1e-9)) with vectors arrowstyle 1 notitle
