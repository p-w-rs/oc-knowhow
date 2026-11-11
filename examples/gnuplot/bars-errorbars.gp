# Grouped comparison with uncertainty, two ways. Left: clustered bars from zero with 95% CI error bars (amounts,
# where zero matters). Right: dot + interval on a value axis (estimates; zero need not be shown), sorted by value.
load "_common.gp"
$acc << EOD
# dataset   A_mean A_lo A_hi   B_mean B_lo B_hi
CIFAR       0.912 0.905 0.919  0.931 0.925 0.937
SVHN        0.955 0.950 0.960  0.958 0.953 0.963
ImageNet    0.761 0.752 0.770  0.784 0.776 0.792
Speech      0.842 0.828 0.856  0.839 0.824 0.854
EOD
set multiplot layout 1,2 margins 0.08,0.98,0.14,0.9 spacing 0.1
# 1. bars: histogram errorbars wants (value, low, high) per bar
set title "Bars (start at 0)"
set style data histograms
set style histogram errorbars gap 1 linewidth 1.5
set style fill solid 0.85 border -1
set boxwidth 0.9
set yrange [0:1]; set ylabel "Accuracy (mean, 95% CI, 5 seeds)"
set xtics nomirror scale 0
set key top right horizontal
plot $acc using 2:3:4:xtic(1) linecolor 1 title "A", '' using 5:6:7 linecolor 2 title "B"
# 2. dot + interval: x = estimate with xerrorbars, y = category (sorted by A); offsets keep A and B apart
set title "Dot + interval (zoomed)"
set style data points
unset ylabel; set xlabel "Accuracy"
set xrange [0.74:0.98]; set yrange [-0.6:3.6]
set ytics ("ImageNet" 0, "Speech" 1, "CIFAR" 2, "SVHN" 3) scale 0
set xtics scale 1
set key top left vertical
rank(s) = s eq "ImageNet" ? 0 : s eq "Speech" ? 1 : s eq "CIFAR" ? 2 : 3
plot $acc using 2:(rank(strcol(1))+0.12):3:4 with xerrorbars linecolor 1 pointtype 7 title "A", \
     ''   using 5:(rank(strcol(1))-0.12):6:7 with xerrorbars linecolor 2 pointtype 5 title "B"
unset multiplot
