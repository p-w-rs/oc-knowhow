#module_parameters (SYSTEM := Unit_System.METRIC) {
    Unit_System :: enum { METRIC; IMPERIAL; }
};

from_meters :: (m: float) -> float {
    #if SYSTEM == .METRIC return m;
    else                  return m * 3.28084;
}

unit_name :: () -> string {
    #if SYSTEM == .METRIC return "m";
    else                  return "ft";
}
