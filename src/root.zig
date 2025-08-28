const std = @import("std");

fn trimTag(string: []const u8) []const u8 {
    return std.mem.trim(
        u8,
        string,
        " \n\r\t",
    );
}

pub const TagType = enum { StartTag, EndTag };

pub fn tagTypeFromTagText(tag_text: []const u8) TagType {
    var tag_type = TagType.StartTag;
    if (std.mem.startsWith(u8, tag_text, "</")) {
        tag_type = TagType.EndTag;
    }
    return tag_type;
}

pub fn elementFromTagText(
    allocator: std.mem.Allocator,
    tag_text: []const u8,
    tag_type: TagType,
    nested: usize,
) !Element {
    var skip_num_start: usize = 1;
    if (tag_type == TagType.EndTag) {
        skip_num_start = 2;
    }
    const skip_num_end = std.mem.indexOf(u8, tag_text, " ") orelse
        std.mem.indexOf(u8, tag_text, ">") orelse
        unreachable;
    const tag_name = tag_text[skip_num_start..skip_num_end];
    return Element{
        .tag_name = tag_name,
        .tag_text = tag_text,
        .nested = nested,
        .items = try std.array_list.Managed(*Element).initCapacity(allocator, 0),
        //.parent = null,
    };
}

const ElementTextIterator = struct {
    haystack: []const u8,
    pub fn next(self: *ElementTextIterator) ?struct { []const u8, TagType } {
        const start = std.mem.indexOf(u8, self.haystack, "<").?;
        const end = std.mem.indexOf(u8, self.haystack[start..], ">").? + 1;
        const result = self.parse(start, end);
        self.haystack = self.haystack[start + end ..];
        return result;
    }
    pub fn parse(
        self: *ElementTextIterator,
        start: usize,
        end: usize,
    ) struct { []const u8, TagType } {
        const tag_text = self.haystack[start .. start + end];
        const tag_type = tagTypeFromTagText(tag_text);
        return .{ tag_text, tag_type };
    }
};

pub fn parseString(allocator: std.mem.Allocator, string: []u8) !Document {
    // Create a default root element to hold the tree structure.
    var root = try Element.default(allocator);
    var document = Document{
        .items = root.items.items,
        .all = std.array_list.Managed(Element).init(allocator),
    };
    var nested: usize = 0;
    var iterator = ElementTextIterator{ .haystack = string };
    while (iterator.next()) |tag| {
        std.debug.print("Found text: {s}\n", .{tag[0]});
        var element = try elementFromTagText(
            allocator,
            tag[0],
            tag[1],
            nested,
        );
        try root.append(nested, &element);
        if (tag[1] == TagType.StartTag) {
            nested += 1;
        }
        if (tag[1] == TagType.EndTag) {
            nested -= 1;
        }
        try document.all.append(element);
    }
    return document;
}

pub const Element = struct {
    //parent: ?Element,
    tag_name: []const u8,
    tag_text: []const u8,
    nested: usize,
    items: std.array_list.Managed(*Element),

    fn default(allocator: std.mem.Allocator) !Element {
        return Element{
            //.parent = null,
            .tag_name = "document",
            .tag_text = "<!DOCTYPE html>",
            .nested = 0,
            .items = try std.array_list.Managed(*Element).initCapacity(allocator, 0),
        };
    }

    /// User passes nested 3, close tag
    fn append(
        self: *Element,
        nested: usize,
        element: *Element,
    ) !void {
        if (nested == 0) {
            std.debug.print("adding child {s} to: {s}\n", .{ element.tag_name, self.tag_name });
            return try self.items.append(element);
        }
        std.debug.print("skip adding child {s} to: {s} nested={d}\n", .{ element.tag_name, self.tag_name, nested });
        var child = self.items.getLast();
        return try child.append(nested - 1, element);
    }
};

pub const Document = struct {
    items: []*Element,
    all: std.array_list.Managed(Element),
};

// zig test --test-filter "simple" src/root.zig
test "parse html from file simple" {
    const html = try std.fs.cwd().readFileAlloc(
        std.heap.page_allocator,
        "./samples/simple.html",
        999999,
    );
    const document = try parseString(std.heap.page_allocator, html);
    const htmlElement = document.items[0];
    try std.testing.expectEqualStrings(htmlElement.tag_name, "html");
    const headElement = htmlElement.items.items[0];
    try std.testing.expectEqualStrings(headElement.tag_name, "head");
    const titleElement = headElement.items.items[0];
    try std.testing.expectEqualStrings(titleElement.tag_name, "title");
}
