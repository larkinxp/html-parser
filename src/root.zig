const std = @import("std");

pub const ScanMode = enum {
    NextElement,
    TagName,
    TagText,
};

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
        .children = try std.array_list.Managed(Element).initCapacity(allocator, 0),
        //.parent = null,
    };
}

pub fn parseString(allocator: std.mem.Allocator, string: []u8) !Dom {
    // Create a default root element to hold the tree structure.
    var root = try Element.default(allocator);
    var nested: usize = 0;
    var closed_tag = false;
    for (string, 0..) |char, i| {
        if (std.mem.eql(u8, &[_]u8{char}, "<")) {
            if (std.mem.indexOf(u8, string[i..], ">")) |last_i| {
                const tag_text = trimTag(string[i .. i + 1 + last_i]);
                const tag_type = tagTypeFromTagText(tag_text);

                std.debug.print("Found text: {s}\n", .{tag_text});

                const element = try elementFromTagText(
                    allocator,
                    tag_text,
                    tag_type,
                    nested,
                );

                try root.appendChild(nested, element, closed_tag);

                std.debug.print("root: {}\n", .{root.children});

                if (tag_type == TagType.StartTag) {
                    closed_tag = false;
                    nested += 1;
                }

                // closing tag, deduct index and set parent to previous element
                if (tag_type == TagType.EndTag) {
                    closed_tag = true;
                    nested -= 1;
                }

                //for (root.children.items) |item1| {
                //std.debug.print("\t{s}\n", .{item1.tag_text});
                //for (item1.children.items) |item2| {
                //std.debug.print("\t\t{s}\n", .{item2.tag_text});
                //for (item2.children.items) |item3| {
                //std.debug.print("\t\t{s}\n", .{item3.tag_text});
                //}
                //}
                //}
            }
        }
    }
    std.debug.print("\n\n\n", .{});
    for (root.children.items) |dom_child| {
        std.debug.print(
            "DomChildren: TagName={s} ChildCount={d}\n",
            .{ dom_child.tag_name, dom_child.children.items.len },
        );
        for (dom_child.children.items) |child1| {
            std.debug.print(
                "DomChildren: child1: TagName={s} ChildCount={d}\n",
                .{ child1.tag_name, child1.children.items.len },
            );
        }
    }
    return Dom{ .children = root.children.items };
}

pub const Element = struct {
    //parent: ?Element,
    tag_name: []const u8,
    tag_text: []const u8,
    nested: usize,
    children: std.array_list.Managed(Element),

    fn default(allocator: std.mem.Allocator) !Element {
        return Element{
            //.parent = null,
            .tag_name = "dom",
            .tag_text = "<dom></dom>",
            .nested = 0,
            .children = try std.array_list.Managed(Element).initCapacity(allocator, 0),
        };
    }

    /// User passes nested 3, close tag
    fn appendChild(
        self: *Element,
        nested: usize,
        element: Element,
        closed_tag: bool,
    ) !void {
        std.debug.print(
            "appendChild: nested={d} insert_element_tag={s} parent_element_tag={s} closed_tag={any} append1={any}\n",
            .{ nested, element.tag_text, self.tag_text, closed_tag, nested == 0 },
        );
        if (nested == 0) {
            return try self.children.append(element);
        }
        var child = self.children.items[self.children.items.len - 1];
        return try child.appendChild(nested - 1, element, closed_tag);
    }
};

pub const Dom = struct {
    children: []Element,
};

test "simple" {
    const html = try std.fs.cwd().readFileAlloc(
        std.heap.page_allocator,
        "./samples/simple.html",
        999999,
    );
    const dom = try parseString(std.heap.page_allocator, html);
    const htmlElement = dom.children[0];
    try std.testing.expectEqualStrings(htmlElement.tag_name, "html");
    const headElement = htmlElement.children.items[0];
    try std.testing.expectEqualStrings(headElement.tag_name, "head");
    const titleElement = headElement.children.items[0];
    try std.testing.expectEqualStrings(titleElement.tag_name, "title");
}
