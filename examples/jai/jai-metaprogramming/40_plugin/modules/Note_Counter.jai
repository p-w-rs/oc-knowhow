// A metaprogram plugin: a module that defines get_plugin() -> *Metaprogram_Plugin. The default
// metaprogram imports it for `+Note_Counter ...`, passes it every argument up to the next `+`
// (or a lone `-`), and calls its hooks:
//   init(p, options) -> bool   parse options; returning false aborts the build
//   before_intercept(p, *flags) / add_source(p)   before compilation starts (unused here)
//   message(p, message)        every message of the target workspace
//   finish(p) / shutdown(p)    after the last message
// Plugins are imported by the METAPROGRAM's workspace, so -import_dir (which belongs to the target
// workspace) does not help: put them in a `modules/` folder next to the first file, or pass the
// compiler developer option `--- import_dir DIR` (jai main.jai +Note_Counter --- import_dir DIR).
#import "Basic";
#import "Compiler";
#import "String";
#import "Sort";

Note_Counter :: struct {
    #as using base: Metaprogram_Plugin;    // so *Note_Counter casts to *Metaprogram_Plugin and back
    note := "Audit";
    found: [..] string;
}

get_plugin :: () -> *Metaprogram_Plugin {
    p := New(Note_Counter);
    p.init     = init;
    p.message  = message;
    p.finish   = finish;
    p.shutdown = shutdown;
    p.log_help = (p: *Metaprogram_Plugin) { log("-note NAME   count declarations tagged @NAME (default Audit)\n"); };
    return p;
}

init :: (p: *Metaprogram_Plugin, options: [] string) -> bool {
    me := cast(*Note_Counter) p;
    i := 0;
    while i < options.count {
        if options[i] == "-note" && i + 1 < options.count {
            me.note = options[i + 1];
            i += 2;
        } else {
            log_error("Note_Counter: unknown option '%'\n", options[i]);
            return false;
        }
    }
    return true;
}

message :: (p: *Metaprogram_Plugin, m: *Message) {
    if m.kind != .TYPECHECKED return;
    me := cast(*Note_Counter) p;
    tc := cast(*Message_Typechecked) m;
    for tc.procedure_headers {
        header := it.expression;
        for header.notes if it.text == me.note  array_add(*me.found, copy_string(header.name));
    }
}

finish :: (p: *Metaprogram_Plugin) {
    me := cast(*Note_Counter) p;
    quick_sort(me.found, compare_strings);
    print("[Note_Counter] @%: % (%)\n", me.note, join(..me.found, separator = ", "), me.found.count);
}

shutdown :: (p: *Metaprogram_Plugin) {
    me := cast(*Note_Counter) p;
    array_free(me.found);
    free(me);
}
