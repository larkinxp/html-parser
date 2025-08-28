const std = @import("std");

pub const ToStringOptions = struct {
    whitespace: bool = false,
    nested: usize = 0,
};

/// To avoid duplicate field names, we can add underscores. These need to be stripped
/// from the output though!
fn stripUnderscoresFromTagName(input: []const u8) []const u8 {
    const idx = std.mem.indexOf(u8, input, "_") orelse return input;
    return input[0..idx];
}

fn isText(input: anytype) bool {
    return switch (input) {
        .pointer => |p| (p.size == .slice and p.child == u8) or (p.size == .one and @typeInfo(p.child) == .array and @typeInfo(p.child).array.child == u8),
        // .array => technically, but you need to use &
        else => false,
    };
}

fn writeTabs(options: *ToStringOptions, data: *std.array_list.Managed([]const u8)) !void {
    if (!options.whitespace) return;
    var z: usize = 0;
    while (z < options.nested) {
        try data.append("\t");
        z += 1;
    }
}

fn writeNewLine(options: *ToStringOptions, data: *std.array_list.Managed([]const u8)) !void {
    if (!options.whitespace) return;
    try data.append("\n");
}

fn isAttribute(field: std.builtin.Type.StructField) bool {
    return !std.mem.eql(u8, field.name, "h1") and !std.mem.eql(u8, field.name, "text");
}

fn writeElementAttributes(
    data: *std.array_list.Managed([]const u8),
    html_struct: anytype,
    field: std.builtin.Type.StructField,
) !void {
    const field_info = @typeInfo(field.type);
    const fields = field_info.@"struct".fields;
    comptime var ix = 0;
    inline while (ix < fields.len) {
        const field2 = fields[ix];
        const field2_info = @typeInfo(field2.type);
        if (isAttribute(field2) and field2_info != .@"struct") {
            const f2 = @field(html_struct, field.name);
            const field2_value = @field(f2, field2.name);
            if (isText(field2_info) and !std.mem.eql(u8, field2.name, "0")) {
                try data.append(" ");
                try data.append(field2.name);
                if (@TypeOf(field2_value) != @TypeOf(null)) { // check must be here for compiler
                    try data.append("=\"");
                    try data.append(field2_value);
                    try data.append("\"");
                }
            } else if (@TypeOf(field2_value) == @TypeOf(null)) {
                try data.append(" ");
                try data.append(field2.name);
            }
        }
        ix += 1;
    }
}

fn incrementNested(options: *ToStringOptions) void {
    options.nested += @as(usize, 1);
}

fn decrementNested(options: *ToStringOptions) void {
    options.nested -= @as(usize, 1);
}

fn hasSpecialName(tag_name: []const u8) []const u8 {
    if (std.mem.eql(u8, tag_name, "doctype")) {
        return "!DOCTYPE";
    }
    return tag_name;
}

/// Will be called after tag_name is mutated. Eg. to be all caps for DOCTYPE and to remove underscores from duplicate field names
fn hasClosingTag(tag_name: []const u8) bool {
    if (std.mem.eql(u8, tag_name, "!DOCTYPE") or std.mem.eql(u8, tag_name, "meta") or std.mem.eql(u8, tag_name, "link") or std.mem.eql(u8, tag_name, "img")) {
        return false;
    }
    return true;
}

fn shouldWrapText(options: *ToStringOptions, tag_name: []const u8) bool {
    if (!options.whitespace) return false;
    if (std.mem.eql(u8, tag_name, "title")) {
        return false;
    }
    return true;
}

fn writeOpeningTag(
    html_struct: anytype,
    options: *ToStringOptions,
    data: *std.array_list.Managed([]const u8),
    field: std.builtin.Type.StructField,
    stripped_field_name: []const u8,
) !void {
    try writeTabs(options, data);
    try data.append("<");
    try data.append(stripped_field_name);

    // write data fields within opening tag
    try writeElementAttributes(data, html_struct, field);

    // write the end of the opening tag
    try data.append(">");
    if (shouldWrapText(options, stripped_field_name)) {
        try writeNewLine(options, data);
    }
}

fn writeClosingTag(
    options: *ToStringOptions,
    data: *std.array_list.Managed([]const u8),
    stripped_field_name: []const u8,
) !void {
    decrementNested(options);
    if (hasClosingTag(stripped_field_name)) {
        if (shouldWrapText(options, stripped_field_name)) {
            try writeTabs(options, data);
        }
        try data.append("</");
        try data.append(stripped_field_name);
        try data.append(">");
        // write new line following closing tag, but not if this is the final element
        if (options.nested > 0) {
            try writeNewLine(options, data);
        }
    }
}

// Process field name to its output value.
// Strip underscores (fields may have underscores to avoid duplicate names).
// Also mutates some tags that have special titles like doctype.
// - div => div
// - div_1 => div
// - div_2 => div
// - doctype => !DOCTYPE
fn processFieldName(field_name: []const u8) []const u8 {
    var stripped_field_name = stripUnderscoresFromTagName(field_name);
    stripped_field_name = hasSpecialName(stripped_field_name);
    return stripped_field_name;
}

fn findTextField(
    html_struct: anytype,
    field: std.builtin.Type.StructField,
) !?[]const u8 {
    comptime var iy = 0;
    const fields2_info = @typeInfo(field.type);
    const fields2_fields = fields2_info.@"struct".fields;
    inline while (iy < fields2_fields.len) {
        const field2 = fields2_fields[iy];
        const field3_info = @typeInfo(field2.type);
        // "0" is the tuple name of field when no key is specified just text
        if (field3_info != .@"struct" and (std.mem.eql(u8, field2.name, "text") or std.mem.eql(u8, field2.name, "0"))) {
            const f2 = @field(html_struct, field.name);
            const field2_value = @field(f2, field2.name);
            return field2_value;
        }
        iy += 1;
    }
    return null;
}

pub fn toString(
    allocator: std.mem.Allocator,
    html_struct: anytype,
    options_in: ToStringOptions,
) ![]const u8 {
    var options = options_in;

    const HtmlStructType = @TypeOf(html_struct);
    const html_struct_type_info = @typeInfo(HtmlStructType);
    if (html_struct_type_info != .@"struct") {
        @compileError("Expected a struct to html.toString()");
    }

    var data = std.array_list.Managed([]const u8).init(allocator);

    const fields_info = html_struct_type_info.@"struct".fields;
    comptime var i = 0;
    inline while (i < fields_info.len) {
        const field = fields_info[i];
        if (@typeInfo(field.type) == .@"struct") {
            // Process input struct field name. Returns its output tag.
            // Removes underscores and changes special tag names.
            const stripped_field_name = processFieldName(field.name);

            // Append the opening tag to `data` variable.
            try writeOpeningTag(
                html_struct,
                &options,
                &data,
                field,
                stripped_field_name,
            );

            if (try findTextField(html_struct, field)) |text| {
                incrementNested(&options);
                // handle options.wrap_text
                // (should add tabs if wrap_text is fale which also requires options.whitespace = true)
                if (shouldWrapText(&options, stripped_field_name)) {
                    try writeTabs(&options, &data);
                }
                decrementNested(&options);
                try data.append(text);
                if (shouldWrapText(&options, stripped_field_name)) {
                    try writeNewLine(&options, &data);
                }
            }

            incrementNested(&options);

            const s1 = try toString(
                allocator,
                @field(html_struct, field.name),
                options,
            );

            try data.append(s1);

            // write closing tag
            try writeClosingTag(
                &options,
                &data,
                stripped_field_name,
            );
        }
        i += 1;
    }

    const buffer = try copyItems(allocator, data);
    return buffer;
}

fn copyItems(allocator: std.mem.Allocator, data: std.array_list.Managed([]const u8)) ![]u8 {
    // Get total length for the new buffer by counting the length of each item.
    var totalLength: usize = 0;
    for (data.items) |item| {
        totalLength += item.len;
    }
    // Allocate a new buffer with the expected length.
    var buffer: []u8 = try allocator.alloc(u8, totalLength);
    var offset: usize = 0;
    // Copy the strings into the new buffer.
    for (data.items) |item| {
        std.mem.copyForwards(u8, buffer[offset..], item);
        offset += item.len;
    }
    return buffer;
}

// zig test --test-filter "template to string simple" src/template.zig
test "template to string simple" {
    const html_struct = .{
        .doctype = .{ .html = null },
        .html = .{
            .head = .{
                .title = .{"Page title"},
                .meta = .{ .charset = "utf-8" },
                .meta_2 = .{ .charset = "viewport", .content = "width=device-width, initial-scale=1.0" },
                .link = .{ .rel = "icon", .href = "data://test..." },
                .style = .{".css { color: red; }"},
                .style_2 = .{"#body { background-color: green; }"},
            },
            .body = .{
                .id = "body",
                .class = "css mb-0 p-2",
                .h1 = .{ .class = "title", .text = "Page content title" },
            },
            .footer = .{
                .text = "More footer text",
                .class = "footer mb-0",
                .h5 = .{"Footer"},
            },
        },
    };
    const html = try toString(
        std.heap.page_allocator,
        html_struct,
        .{ .whitespace = false },
    );
    //std.debug.print("{s}\n", .{html});
    try std.testing.expectEqualStrings(html, "<!DOCTYPE html><html><head><title>Page title</title><meta charset=\"utf-8\"><meta charset=\"viewport\" content=\"width=device-width, initial-scale=1.0\"><link rel=\"icon\" href=\"data://test...\"><style>.css { color: red; }</style><style>#body { background-color: green; }</style></head><body id=\"body\" class=\"css mb-0 p-2\"><h1 class=\"title\">Page content title</h1></body><footer class=\"footer mb-0\">More footer text<h5>Footer</h5></footer></html>");
}

// zig test --test-filter "template to string complex" src/template.zig
test "template to string complex" {
    const head = .{
        .title = .{"Page title"},
        .link = .{ .rel = "shortcut icon", .href = "https://path/to/favicon.ico" },
        .link_2 = .{ .rel = "apple-touch-icon", .href = "https://path/to/touch-icon.png" },
        .link_3 = .{ .rel = "image_src", .href = "https://path/to/image-source.jpg" },
        .link_4 = .{ .rel = "search", .type = "application/opensearchdescription+xml", .title = "Search title", .href = "https://path/to/favicon.ico" },
        .link_5 = .{ .rel = "canonical", .href = "https://canonical/link/to" },
        .meta = .{ .name = "viewport", .content = "width=device-width, height=device-height, initial-scale=1.0, minimum-scale=1.0" },
        .meta_2 = .{ .property = "og:type", .content = "website" },
        .meta_3 = .{ .property = "og:url", .content = "https://path/to/my/website" },
        .meta_4 = .{ .property = "og:site_name", .content = "Site Title" },
        .meta_5 = .{ .property = "og:image", .itemprop = "image primary-image", .content = "https://path/to/image.png" },
        .script = .{
            .type = "application/javascript",
            .text = "alert('test');",
        },
    };
    const html_struct = .{
        .doctype = .{ .html = null },
        .html = .{
            .itemscope = null,
            .itemtype = "https://schema.org/QAPage",
            .lang = "en",
            .head = head,
            .body = .{
                .id = "body",
                .class = "css mb-0 p-2",
                .h1 = .{ .class = "title", .text = "Page content title" },
            },
            .footer = .{
                .text = "More footer text",
                .class = "footer mb-0",
                .h5 = .{"Footer"},
            },
        },
    };
    const html = try toString(
        std.heap.page_allocator,
        html_struct,
        .{ .whitespace = false },
    );
    //std.debug.print("{s}\n", .{html});
    try std.testing.expectEqualStrings(html, "<!DOCTYPE html><html itemscope itemtype=\"https://schema.org/QAPage\" lang=\"en\"><head><title>Page title</title><link rel=\"shortcut icon\" href=\"https://path/to/favicon.ico\"><link rel=\"apple-touch-icon\" href=\"https://path/to/touch-icon.png\"><link rel=\"image_src\" href=\"https://path/to/image-source.jpg\"><link rel=\"search\" type=\"application/opensearchdescription+xml\" title=\"Search title\" href=\"https://path/to/favicon.ico\"><link rel=\"canonical\" href=\"https://canonical/link/to\"><meta name=\"viewport\" content=\"width=device-width, height=device-height, initial-scale=1.0, minimum-scale=1.0\"><meta property=\"og:type\" content=\"website\"><meta property=\"og:url\" content=\"https://path/to/my/website\"><meta property=\"og:site_name\" content=\"Site Title\"><meta property=\"og:image\" itemprop=\"image primary-image\" content=\"https://path/to/image.png\"><script type=\"application/javascript\">alert('test');</script></head><body id=\"body\" class=\"css mb-0 p-2\"><h1 class=\"title\">Page content title</h1></body><footer class=\"footer mb-0\">More footer text<h5>Footer</h5></footer></html>");
}
