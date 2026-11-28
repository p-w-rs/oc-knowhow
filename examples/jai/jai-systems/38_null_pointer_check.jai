// null_pointer_check (on in debug builds) covers the automatic dereference that happens when a
// *T is passed where a T parameter is expected. A plain p.field through a null pointer is NOT
// checked: it is a hardware fault reported by the crash handler (wording differs per OS:
// Linux "SEGV_MAPERR ... Null Pointer Exception", macOS "SEGV_ACCERR ... read-only memory").
// EXPECT-EXIT: 1
// EXPECT-CONTAINS: Null pointer check failed: Argument 1 is undergoing an automatic dereference, but the pointer is null.
#import "Basic";

Settings :: struct { volume: int; muted: bool; }

describe :: (s: Settings) -> string {    // takes the struct by value
    return tprint("volume % muted %", s.volume, s.muted);
}

main :: () {
    current: *Settings;                  // never assigned
    print("%\n", describe(current));     // *Settings auto-dereferenced into Settings: checked
}
