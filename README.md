HTML parsing and templating in Zig.

##### Features
- Write Zig structs and then convert to HTML.
- Parse HTML for querying purposes.

##### Tests
- `zig test --test-filter "parse html from file simple" src/root.zig`
- `zig test -femit-docs --test-filter "template to string simple" src/template.zig`
- `zig test -femit-docs --test-filter "template to string complex" src/template.zig`