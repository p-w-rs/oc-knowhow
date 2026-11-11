# Volumetric view of 3D data: the density of a point cloud as an isosurface (e.g. embeddings, particles, detections).
# vfill adds a smooth kernel around every data point into a voxel grid; the isosurface encloses the dense regions.
load "_common.gp"
set print $cloud
do for [i=1:1500] { c = (rand(0) < 0.5) ? -0.8 : 0.8; print sprintf("%g %g %g", c + 0.35*invnorm(rand(0)), 0.35*invnorm(rand(0)), 0.5*c + 0.35*invnorm(rand(0))) }
unset print
set vgrid $density size 60
set vxrange [-2:2]; set vyrange [-2:2]; set vzrange [-2:2]   # the active grid's ranges; set after `set vgrid`
vfill $cloud using 1:2:3:(0.5):(exp(-(VoxelDistance/0.25)**2))
set xrange [-2:2]; set yrange [-2:2]; set zrange [-2:2]
set xyplane at -2
set view 62, 30, 1.2
set xlabel "x"; set ylabel "y"; set zlabel "z"
# Depth-sorted, semi-transparent faces with thin edges keep the shape and what is behind it readable.
set pm3d depth border linecolor "#0072B2" linewidth 0.3
set style fill transparent solid 0.35
splot $cloud every 5 using 1:2:3 with dots linecolor rgb "#888888" notitle, \
      $density with isosurface level 8 fillcolor "#0072B2" notitle
