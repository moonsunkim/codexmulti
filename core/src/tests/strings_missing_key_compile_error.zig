const strings = @import("strings");

comptime {
    _ = strings.system.text(.not_in_catalog);
}
