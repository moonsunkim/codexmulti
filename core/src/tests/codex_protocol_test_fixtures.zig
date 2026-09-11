pub fn frame(comptime body: []const u8) []const u8 {
    return body ++ "\n";
}

pub fn resultFrame(comptime id: []const u8, comptime result: []const u8) []const u8 {
    return frame("{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"result\":" ++ result ++ "}");
}
