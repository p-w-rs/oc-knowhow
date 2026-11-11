# 3D surface with lighting and contours projected on the base.
load "_common.gp"
set xrange [-2:2]; set yrange [-2:2]
set isosamples 60, 60; set samples 60, 60
f(x,y) = exp(-(x**2+y**2)) * cos(3*x) * sin(2*y)
set palette cubehelix
set pm3d depthorder lighting primary 0.6 specular 0.3 border lw 0.3 lc "#33333333"
unset grid                      # the shared 2D grid would clutter the 3D base
set contour base; set cntrparam levels 10
set cntrlabel onecolor          # all contour lines in one color instead of cycling line types
set view 55, 35, 1, 1.1
set xyplane relative 0.15
set xlabel "x"; set ylabel "y"; set zlabel "f(x,y)" rotate parallel
set colorbox vertical user origin 0.9,0.3 size 0.02,0.45
splot f(x,y) with pm3d linecolor rgb "#444444" notitle
