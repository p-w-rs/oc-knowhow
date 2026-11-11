# Compare distributions honestly: every point (jittered), box summary, and a smoothed density (violin).
load "_common.gp"
set print $data
do for [g=1:3] { do for [i=1:60] { print sprintf("%d %.4f", g, invnorm(rand(0))*(0.6+0.2*g) + 2.0*sqrt(g)) } }
unset print
# 1. densities first (before setting the x range for the figure: kdensity samples over the current x range)
set table $violins
set samples 200
set xrange [*:*]
# weight 1/n per point makes each curve a proper density (area 1); columns of the table: value, density
plot for [g=1:3] $data using ($1==g ? $2 : NaN):(1.0/60) smooth kdensity bandwidth 0.35
unset table
# 2. figure: violin (mirrored density) + box summary + every point jittered
set xrange [0.3:3.7]
set xtics ("Baseline" 1, "+ Aug" 2, "+ Aug + Distill" 3)
set ylabel "Score"
set jitter overlap 1 spread 0.25
set style fill solid 0.15 border
set style boxplot nooutliers
set boxwidth 0.22
plot for [g=1:3] $violins index (g-1) using (g + 0.8*$2):1 with lines linecolor g notitle, \
     for [g=1:3] $violins index (g-1) using (g - 0.8*$2):1 with lines linecolor g notitle, \
     for [g=1:3] $data using (g):($1==g ? $2 : NaN) with boxplot linecolor rgb "#555555" notitle, \
     $data using 1:2:1 with points pointtype 7 pointsize 0.5 linecolor variable notitle
