# Small multiples: the same plot per subgroup on shared axes (better than one crowded plot).
load "_common.gp"
set multiplot layout 2,3 title "Error vs model size, by dataset" margins 0.08,0.98,0.1,0.9 spacing 0.06,0.12
set xrange [6:11]; set yrange [0:0.6]
set logscale x 10; set xrange [1e6:1e11]
set format x "10^{%L}"
names = "CIFAR SVHN ImageNet Speech Text Tabular"
do for [k=1:6] {
  set title word(names, k)
  if (k > 3) { set xlabel "parameters" } else { unset xlabel }
  if (k % 3 == 1) { set ylabel "error" } else { unset ylabel }
  plot [1e6:1e11] 0.05*k/3 + 0.5*(x/1e6)**(-0.08*k/3 - 0.05) with lines linecolor k notitle
}
unset multiplot
