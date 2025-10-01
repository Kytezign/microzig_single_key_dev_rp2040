//! Hacked together USB logging and debug control
//! This works using the Sept 2025 version of microzig and 0.15.1 zig release
//! Had to update the buffer size of cdc.zig and fix the get_readable_len fuction in src utilities (see latest main changes).
//! ALso updated line_state:
//!                     .SetControlLineState => {
//!                        switch (stage) {
//!                            .Setup => {
//!                                self.device.?.control_ack(setup);
//!                            },
//!                            .Ack => {
//!                                // Set DTR and RTS
//!                                self.line_state = setup.request;
//!                            },
//!                            else => {},
//!                        }

const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const rom = rp2xxx.rom;
const usb = rp2xxx.usb;
const peripherals = microzig.chip.peripherals;

const usb_dev = rp2xxx.usb.Usb(.{});

const usb_config_len = usb.templates.config_descriptor_len + usb.templates.cdc_descriptor_len;
const usb_config_descriptor =
    usb.templates.config_descriptor(1, 2, 0, usb_config_len, 0xc0, 100) ++
    usb.templates.cdc_descriptor(0, 4, usb.Endpoint.to_address(1, .In), 8, usb.Endpoint.to_address(2, .Out), usb.Endpoint.to_address(2, .In), 64);

var driver_cdc: usb.cdc.CdcClassDriver(usb_dev) = .{};
var drivers = [_]usb.types.UsbClassDriver{driver_cdc.driver()};

// This is our device configuration
pub var DEVICE_CONFIGURATION: usb.DeviceConfiguration = .{
    .device_descriptor = &.{
        .descriptor_type = usb.DescType.Device,
        .bcd_usb = 0x0200,
        .device_class = 0xEF,
        .device_subclass = 2,
        .device_protocol = 1,
        .max_packet_size0 = 64,
        .vendor = 0x2E8A,
        .product = 0x000a,
        .bcd_device = 0x0100,
        .manufacturer_s = 1,
        .product_s = 2,
        .serial_s = 0,
        .num_configurations = 1,
    },
    .config_descriptor = &usb_config_descriptor,
    .lang_descriptor = "\x04\x03\x09\x04", // length || string descriptor (0x03) || Engl (0x0409)
    .descriptor_strings = &.{
        &usb.utils.utf8_to_utf16_le("Raspberry Pi"),
        &usb.utils.utf8_to_utf16_le("Pico Test Device"),
        &usb.utils.utf8_to_utf16_le("someserial"),
        &usb.utils.utf8_to_utf16_le("Board CDC"),
    },
    .drivers = &drivers,
};

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}
var _initialized: bool = false;
var _watch_boot_cmd = true;

/// Initalized USB interface and logging.
/// If watch_boot is enable it will also watch for a magic byte sequence to send the device into boot mode.
pub fn init(watch_boot_cmd: bool, wait_terminal_conn: bool) void {
    usb_dev.init_clk();
    // Then initialize the USB device using the configuration defined above
    usb_dev.init_device(&DEVICE_CONFIGURATION) catch unreachable;
    const old_state = driver_cdc.line_state;
    _initialized = true;
    _watch_boot_cmd = watch_boot_cmd;

    // Waits for terminal connection.
    if (wait_terminal_conn) {
        while (driver_cdc.line_state == 0) {
            usb_dev.task(false) catch unreachable;
        }
    }
    write("================ Started Logging ==0b{b} -> 0b{b}\r\n", .{ old_state, driver_cdc.line_state });
}

/// Must be called regularly to ensure proper USB functionality
pub fn loop_task() void {
    std.debug.assert(_initialized);
    usb_dev.task(false) catch unreachable;
    if (_watch_boot_cmd) {
        const msg = read();
        if (msg.len > 0) {
            if (std.mem.eql(u8, "magiccode1234", msg)) {
                rom.reset_to_usb_boot();
                @panic("Resetting to Bootloader!");
            }
        }
    }
}

var usb_rx_buff: [1024]u8 = undefined;

// Receive data from host
// NOTE: Read code was not tested extensively. In case of issues, try to call USB task before every read operation
pub fn read() []const u8 {
    var total_read: usize = 0;
    var read_buff: []u8 = usb_rx_buff[0..];

    while (true) {
        const len = driver_cdc.read(read_buff);
        read_buff = read_buff[len..];
        total_read += len;
        if (len == 0) break;
    }
    return usb_rx_buff[0..total_read];
}

// Transfer data to host
var prev_sof_rd_count: u32 = 0;
/// Not 100% sure why this works but the general idea is that we could override the USB buffer if we don't wait long enough
/// the SOF_RD count is an indicator of activity on the bus - hopefully meaning the buffer is empty.
/// surely a better way to do this in the USB implementation...
fn wait_next() void {
    while (prev_sof_rd_count == peripherals.USB.SOF_RD.read().COUNT) {
        usb_dev.task(false) catch unreachable;
    }
    prev_sof_rd_count = peripherals.USB.SOF_RD.read().COUNT;
}

var usb_tx_buff: [1024]u8 = undefined;

pub fn write(comptime fmt: []const u8, args: anytype) void {
    wait_next();
    const text = std.fmt.bufPrint(&usb_tx_buff, fmt, args) catch &.{};
    var write_buff = text;
    while (write_buff.len > 0) {
        write_buff = driver_cdc.write(write_buff);
        wait_next();
    }
    // Short messages are not sent right away; instead, they accumulate in a buffer, so we have to force a flush to send them
    _ = driver_cdc.write_flush();
}

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_prefix = comptime "[{}.{:0>6}] " ++ level.asText();
    const prefix = comptime level_prefix ++ switch (scope) {
        .default => ": ",
        else => " (" ++ @tagName(scope) ++ "): ",
    };

    const current_time = time.get_time_since_boot();
    const seconds = current_time.to_us() / std.time.us_per_s;
    const microseconds = current_time.to_us() % std.time.us_per_s;
    // write("SOF {}", peripherals.USB.SOF_RD.read().COUNT)

    write(prefix ++ format ++ "\r\n", .{ seconds, microseconds } ++ args);
}
