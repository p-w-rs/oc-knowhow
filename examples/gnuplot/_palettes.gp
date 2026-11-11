# Perceptually uniform, colour-vision-deficiency-friendly palettes that gnuplot does not name (it names only viridis
# and cubehelix). 11 stops sampled from the published tables: batlow and vik (Crameri, Scientific colour maps; cmcrameri tables),
# cividis (Nuñez et al. 2018, as in matplotlib). Usage: load "_palettes.gp"; set palette defined @batlow
batlow  = '(0 "#011959", .1 "#103D5F", .2 "#185562", .3 "#31695B", .4 "#577647", .5 "#828231", .6 "#B38E2F", .7 "#E19752", .8 "#FBA689", .9 "#FDB9C2", 1 "#FACCFA")'
cividis = '(0 "#00224E", .1 "#0C3470", .2 "#35456C", .3 "#50576C", .4 "#666970", .5 "#7D7C78", .6 "#948E77", .7 "#AEA371", .8 "#C8B866", .9 "#E5CF52", 1 "#FEE838")'
# diverging (centre = light): use with a symmetric cbrange around the reference value, e.g. set cbrange [-1:1]
vik     = '(0 "#001261", .1 "#023A7B", .2 "#116496", .3 "#5798B9", .4 "#A7C9DA", .5 "#ECE5E0", .6 "#E1B8A0", .7 "#CC875F", .8 "#B75A26", .9 "#852206", 1 "#590008")'
