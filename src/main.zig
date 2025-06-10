const std = @import("std");
const io = std.io;
const time = std.time;

const Stopwatch = struct {
    start_time: ?i64 = null,
    elapsed_time: i64 = 0,
    is_running: bool = false,

    fn start(self: *Stopwatch) void {
        if (!self.is_running) {
            self.start_time = time.milliTimestamp();
            self.is_running = true;
        }
    }

    fn stop(self: *Stopwatch) void {
        if (self.is_running and self.start_time != null) {
            const current_time = time.milliTimestamp();
            self.elapsed_time += current_time - self.start_time.?;
            self.is_running = false;
            self.start_time = null;
        }
    }

    fn reset(self: *Stopwatch) void {
        self.start_time = null;
        self.elapsed_time = 0;
        self.is_running = false;
    }

    fn getElapsedTime(self: *const Stopwatch) i64 {
        if (self.is_running and self.start_time != null) {
            const current_time = time.milliTimestamp();
            return self.elapsed_time + (current_time - self.start_time.?);
        }
        return self.elapsed_time;
    }
};

fn formatTime(milliseconds: i64) struct { hours: u32, minutes: u32, seconds: u32, millis: u32 } {
    const total_seconds = @divFloor(milliseconds, 1000);
    const millis: u32 = @intCast(@mod(milliseconds, 1000));
    const seconds: u32 = @intCast(@mod(total_seconds, 60));
    const total_minutes = @divFloor(total_seconds, 60);
    const minutes: u32 = @intCast(@mod(total_minutes, 60));
    const hours: u32 = @intCast(@divFloor(total_minutes, 60));

    return .{
        .hours = hours,
        .minutes = minutes,
        .seconds = seconds,
        .millis = millis,
    };
}

fn clearScreen() void {
    const stdout = io.getStdOut().writer();
    stdout.print("\x1b[2J\x1b[H", .{}) catch {};
}

fn hideCursor() void {
    const stdout = io.getStdOut().writer();
    stdout.print("\x1b[?25l", .{}) catch {};
}

fn showCursor() void {
    const stdout = io.getStdOut().writer();
    stdout.print("\x1b[?25h", .{}) catch {};
}

fn restoreTerminal() void {
    showCursor();
    clearScreen();
}

pub fn main() !void {
    const stdout = io.getStdOut().writer();
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var stopwatch = Stopwatch{};
    
    clearScreen();
    hideCursor();
    defer restoreTerminal();
    
    try stdout.print("TUI Stopwatch\n", .{});
    try stdout.print("Commands: [SPACE] Start/Stop | [R] Reset | [Q] Quit\n\n", .{});
    
    var running = true;
    
    // Create a thread for keyboard input
    const KeyboardThread = struct {
        fn run(sw: *Stopwatch, is_running: *bool) !void {
            const reader = io.getStdIn().reader();
            var buffer: [1]u8 = undefined;
            
            while (is_running.*) {
                if (try reader.read(&buffer) > 0) {
                    const key = buffer[0];
                    
                    switch (key) {
                        ' ' => {
                            if (sw.is_running) {
                                sw.stop();
                            } else {
                                sw.start();
                            }
                        },
                        'r', 'R' => {
                            sw.reset();
                        },
                        'q', 'Q' => {
                            is_running.* = false;
                        },
                        else => {},
                    }
                }
            }
        }
    };
    
    const keyboard_thread = try std.Thread.spawn(.{}, KeyboardThread.run, .{ &stopwatch, &running });
    defer keyboard_thread.join();
    
    while (running) {
        clearScreen();
        try stdout.print("TUI Stopwatch\n", .{});
        try stdout.print("Commands: [SPACE] Start/Stop | [R] Reset | [Q] Quit\n\n", .{});
        
        const elapsed = stopwatch.getElapsedTime();
        const formatted = formatTime(elapsed);
        
        try stdout.print("\n\n\t{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}\n\n", .{
            formatted.hours,
            formatted.minutes,
            formatted.seconds,
            formatted.millis,
        });
        
        if (stopwatch.is_running) {
            try stdout.print("\t[RUNNING]\n", .{});
        } else {
            try stdout.print("\t[STOPPED]\n", .{});
        }
        
        time.sleep(50 * time.ns_per_ms);
    }
}