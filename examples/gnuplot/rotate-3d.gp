# Animated rotation of a 3D surface (WebP; use gif with "set terminal gif animate delay 4" if preferred).
if (!exists("out")) out = "rotate-3d.webp"
set terminal webp animate delay 50 size 800,600 font "Helvetica,12"
set output out
set isosamples 40; set samples 40
set xrange [-3:3]; set yrange [-3:3]
set palette viridis; unset colorbox
set pm3d depthorder lighting primary 0.5
set hidden3d
do for [a=0:350:10] {
  set view 60, a
  splot sin(sqrt(x**2+y**2))/sqrt(x**2+y**2+0.01) with pm3d notitle
}
unset output
