# Mean curve with a 95% confidence band per method (e.g. validation accuracy over epochs, several seeds).
load "_common.gp"
$runs << EOD
# epoch  meanA  loA   hiA   meanB  loB   hiB
1   0.52 0.49 0.55  0.50 0.46 0.54
2   0.61 0.58 0.64  0.57 0.53 0.61
4   0.70 0.68 0.72  0.66 0.63 0.69
8   0.77 0.75 0.79  0.74 0.71 0.77
16  0.81 0.80 0.82  0.80 0.78 0.82
32  0.83 0.82 0.84  0.83 0.81 0.85
EOD
set logscale x 2
set xlabel "Epoch"
set ylabel "Validation accuracy"
set yrange [0.4:0.9]
set key top left box opaque title "Mean ± 95% CI (5 seeds)" left
set style fill transparent solid 0.20 noborder
plot $runs using 1:3:4 with filledcurves linecolor 1 notitle, \
     ''   using 1:2 with linespoints linecolor 1 title "Method A", \
     ''   using 1:6:7 with filledcurves linecolor 2 notitle, \
     ''   using 1:5 with linespoints linecolor 2 pointtype 5 title "Method B"
