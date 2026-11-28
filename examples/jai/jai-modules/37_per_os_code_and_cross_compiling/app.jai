// The program being built for several targets. OS, CPU and IS_CROSS_COMPILING are
// compile-time constants of the workspace's target; #if picks code per target and
// the branches not taken are not compiled at all (they may even call APIs that do
// not exist on this OS).

#import "Basic";

#if OS == {
    case .WINDOWS; #load "platform/windows.jai";
    case .MACOS;   #load "platform/macos.jai";
    case .LINUX;   #load "platform/linux.jai";
    case;          #assert false "unsupported OS";
}

main :: () {
    print("target %/%, cross-compiled: %\n", OS, CPU, IS_CROSS_COMPILING);
    print("platform file says: %\n", platform_name());
    print("path separator: %\n", PATH_SEPARATOR_FOR_THIS_EXAMPLE);
}
