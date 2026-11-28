// Cross-compiling from a build metaprogram: a workspace whose os_target/cpu_target
// differ from the host becomes a cross-compiling workspace. Without the target's
// system libraries and linker setup, build OBJECT_FILEs (with
// runtime_support_definitions = .ENTRY_POINT_AND_INIT so the object has main and
// the runtime start-up) and link them on the target, e.g. on Linux:
//     cc -no-pie -o app app_linux_x64.o      (Jai objects are not PIE)
// Checked from macOS arm64 and Linux x64 hosts (0.2.032): Windows x64 COFF and
// Linux x64 ELF objects work; macOS -> Linux EXECUTABLE fails at the link step.
// Pitfall: os_target = .LINUX with cpu_target = .ARM64 silently produced an x86-64
// object; setting llvm_options.target_system_triple = "aarch64-unknown-linux-gnu"
// gives a real aarch64 object.
// EXE: app
// EXPECT-COMPILE: app_windows_x64.obj: COFF x86-64
// EXPECT-COMPILE: app_linux_x64.o: ELF x86-64
// EXPECT-COMPILE: app_linux_arm64_no_triple.o: ELF x86-64
// EXPECT-COMPILE: app_linux_arm64.o: ELF aarch64
// EXPECT-CONTAINS: cross-compiled: false
// EXPECT-CONTAINS: path separator: /

#import "Basic";
#import "Compiler";
#import "File";

#run {
    set_build_options_dc(.{do_output = false});
    build_object("app_windows_x64",           .WINDOWS, .X64);
    build_object("app_linux_x64",             .LINUX,   .X64);
    build_object("app_linux_arm64_no_triple", .LINUX,   .ARM64);
    build_object("app_linux_arm64",           .LINUX,   .ARM64, "aarch64-unknown-linux-gnu");
    for string.["app_windows_x64.obj", "app_linux_x64.o", "app_linux_arm64_no_triple.o", "app_linux_arm64.o"] {
        print("%: %\n", it, object_kind(it));
    }

    // And a normal executable for this host, from the same source.
    w := compiler_create_workspace("host executable");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "app";
    set_build_options(options, w);
    add_build_file("app.jai", w);
}

build_object :: (name: string, os: Operating_System_Tag, cpu: CPU_Tag, triple := "") {
    w := compiler_create_workspace(name);
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_type                 = .OBJECT_FILE;
    options.runtime_support_definitions = .ENTRY_POINT_AND_INIT;
    options.os_target                   = os;
    options.cpu_target                  = cpu;
    options.output_executable_name      = name;
    if triple  options.llvm_options.target_system_triple = triple;
    set_build_options(options, w);
    compiler_begin_intercept(w);
    add_build_file("app.jai", w);
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE  break;
    }
    compiler_end_intercept(w);
}

// Reads the machine field of an ELF or COFF object file.
object_kind :: (path: string) -> string {
    data, ok := read_entire_file(path, log_errors = false);
    if !ok || data.count < 20  return "missing";
    if data[0] == 0x7f && data[1] == #char "E" && data[2] == #char "L" && data[3] == #char "F" {
        machine := (cast(*u16) (data.data + 18)).*;
        if machine == 62   return "ELF x86-64";
        if machine == 183  return "ELF aarch64";
        return tprint("ELF machine %", machine);
    }
    machine := (cast(*u16) data.data).*;
    if machine == 0x8664  return "COFF x86-64";
    if machine == 0xaa64  return "COFF arm64";
    return "unknown";
}
