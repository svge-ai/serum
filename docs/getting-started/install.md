# Installation

Serum requires Zig 0.15.2+.

## Add to your project

```bash
zig fetch --save https://github.com/svge-ai/serum/archive/refs/heads/main.tar.gz
```

Then in `build.zig`:

```zig
const serum_dep = b.dependency("serum", .{
    .target = target,
    .optimize = optimize,
});

const exe = b.addExecutable(.{
    .name = "myapp",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "serum", .module = serum_dep.module("serum") },
        },
    }),
});
```

## Pin to a release

```bash
zig fetch --save https://github.com/svge-ai/serum/archive/refs/tags/v0.1.2.tar.gz
```
