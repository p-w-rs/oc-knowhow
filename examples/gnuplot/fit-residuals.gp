# Curve fit with parameter uncertainties, and a residual panel (always look at residuals).
load "_common.gp"
set print $m
do for [i=1:25] { x=i*0.4; print sprintf("%g %g %g", x, 3.0*exp(-x/2.5)+0.4+0.08*invnorm(rand(0)), 0.08) }
unset print
f(x) = A*exp(-x/tau) + c
A = 1; tau = 1; c = 0.1   # non-zero starting values of the right magnitude
set fit quiet errorvariables
fit f(x) $m using 1:2:3 yerror via A, tau, c
set multiplot layout 2,1 margins 0.12,0.97,0.1,0.95 spacing 0,0.03
set lmargin 10
unset xlabel; set format x ""
set ylabel "signal"
set label 1 sprintf("A = %.2f ± %.2f\ntau = %.2f ± %.2f\nc = %.3f ± %.3f", A, A_err, tau, tau_err, c, c_err) at graph 0.6, graph 0.8
plot $m using 1:2:3 with yerrorbars linecolor 1 notitle, f(x) with lines linecolor 4 notitle
unset label 1
set size 1, 0.3
set format x "%g"; set xlabel "time (s)"; set ylabel "resid./σ"
set yrange [-3:3]
plot $m using 1:(($2-f($1))/$3) with impulses linecolor 1 notitle, 0 with lines linecolor black notitle
unset multiplot
