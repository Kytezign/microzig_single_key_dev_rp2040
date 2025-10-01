//! Very simple demonstration of basic USB based logging
//! See host.zig
const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const peripherals = microzig.chip.peripherals;

const time = rp2xxx.time;
const gpio = rp2xxx.gpio;
const host = @import("host.zig");

const led = gpio.num(25);

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = host.log,
};

pub fn main() !void {
    led.set_function(.sio);
    led.set_direction(.out);
    led.put(1);
    host.init(true, true);
    // Then initialize the USB device using the configuration defined above
    var old: u64 = time.get_time_since_boot().to_us();
    var new: u64 = 0;

    var i: u32 = 0;
    while (true) {
        // You can now poll for USB events
        host.loop_task();
        new = time.get_time_since_boot().to_us();
        if (i < 250 and new > (old + 0)) {
            old = new;
            led.toggle();
            i += 1;
            // std.log.info("Log test: {}\r\nLog test lk: {}", .{ i, i });
            std.log.info("Log test lk: {} {} {}", .{ i, peripherals.USB.SOF_RD.read().COUNT, peripherals.USB.BUFF_STATUS.read().EP0_IN });

            // usb_cdc_write("This vice:: {}\r\n", .{i});
            // std.log.info("0123456789112345678921234567893123456789412345678951234567896123456789712345678981234567899123456789A123456789B123456789C123456789D123456789E123456789F123456789{}\r\n", .{i});
            std.log.info("A111111111B111111111C111111111D111111111E111111111F111111111G111111111H111111111I111111111J111111111K111111111L111111111M111111111N111111111O111111111P111111111Q111111111R111111111S111111111T111111111{}", .{i});
            // usb_cdc_write("This is very very long text sent from RP Pico by USB CDC to your device This is very very long text sent from RP Pico by USB CDC to your device:: {}\r\n", .{i});
        }
    }
}
