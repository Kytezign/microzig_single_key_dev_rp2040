const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) !void {
    const proj_name = "usbtest";
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = proj_name,
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = .ReleaseFast,
        .root_source_file = b.path("src/main.zig"),
    });
    mb.install_firmware(firmware, .{});
    const uf2_path = b.getInstallPath(.prefix, "firmware/" ++ proj_name ++ ".uf2");
    addLoadStep(b, uf2_path);
}

/// Adds a "load" step to the build which will call picotool (must be available in the path)
/// To load the input UF2 to the first found RP2040 in boot mode
/// Then restarts the board.
pub fn addLoadStep(b: *std.Build, uf2_path: []const u8) void {
    const load_uf2_argv = [_][]const u8{ "picotool", "load", uf2_path };
    const load_uf2_cmd = b.addSystemCommand(&load_uf2_argv);
    load_uf2_cmd.setName("picotool Load");
    const restart = [_][]const u8{ "picotool", "reboot" };
    const restart_cmd = b.addSystemCommand(&restart);
    restart_cmd.setName("picotool Restart");
    const load_step = b.step("load", "Loads the uf2 with picotool");
    load_uf2_cmd.step.dependOn(b.getInstallStep());
    restart_cmd.step.dependOn(&load_uf2_cmd.step);
    load_step.dependOn(&restart_cmd.step);
}
