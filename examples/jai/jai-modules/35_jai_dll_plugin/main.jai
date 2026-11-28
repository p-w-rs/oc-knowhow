#import "Basic";

// ,no_static_library: only a shared library exists (needed on Windows when using
// #elsewhere data; harmless elsewhere). #elsewhere declares a Jai-convention symbol
// from that library (#foreign would mean the C convention).
plugin :: #library,no_static_library "plugin";
plugin_square   :: (x: s64) -> s64 #no_context #elsewhere plugin;
plugin_describe :: (values: [] int) -> string #elsewhere plugin;

#add_context frame_counter: int;   // makes this program's #Context differ from the plugin's

main :: () {
    print("plugin_square(12) = %\n", plugin_square(12));
    context.print_style.default_format_array.separator = " | ";
    print("%\n", plugin_describe(.[1, 2, 3]));
}
