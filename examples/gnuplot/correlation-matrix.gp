# Correlation matrix (or any signed matrix: confusion deltas, weight differences) with a diverging palette centred
# on zero, a symmetric color range, and the value printed in each cell in a color that stays readable.
load "_common.gp"
load "_palettes.gp"
$C << EOD
1.00  0.82  0.45 -0.10 -0.62
0.82  1.00  0.38  0.05 -0.48
0.45  0.38  1.00  0.30 -0.20
-0.10 0.05  0.30  1.00  0.15
-0.62 -0.48 -0.20 0.15 1.00
EOD
names = "depth width dropout lr noise"
n = words(names)
set palette defined @vik
set cbrange [-1:1]                              # symmetric: white = 0, equal color steps either side
set cblabel "Pearson r"
set xrange [-0.5:n-0.5]; set yrange [n-0.5:-0.5]  # reversed y: row 1 at the top, like a printed matrix
set size ratio -1
set xtics () nomirror; set ytics () nomirror
do for [i=1:n] { set xtics add (word(names, i) i-1); set ytics add (word(names, i) i-1) }
set xtics scale 0 rotate by 30 right; set ytics scale 0
unset grid; set border 0
plot $C matrix with image pixels notitle, \
     $C matrix using 1:2:(sprintf("%.2f", $3)):(abs($3) > 0.5 ? 0xFFFFFF : 0x222222) with labels textcolor rgb variable notitle
