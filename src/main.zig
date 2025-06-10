const std = @import("std");
const builtin = @import("builtin");
const io = std.io;
const time = std.time;
const os = std.os;

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

// ANSI color codes
const Colors = struct {
    const reset = "\x1b[0m";
    const bright_blue = "\x1b[94m";
    const cyan = "\x1b[96m";
    const dim = "\x1b[2m";
    const bright = "\x1b[1m";
    const blink = "\x1b[5m";
    const reverse = "\x1b[7m";
};

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

fn moveCursor(row: u32, col: u32) void {
    const stdout = io.getStdOut().writer();
    stdout.print("\x1b[{d};{d}H", .{ row, col }) catch {};
}

const Star = struct {
    x: u8,
    y: u8,
    brightness: u8,
    
    fn new(rng: *std.Random.DefaultPrng, width: u8, height: u8) Star {
        return .{
            .x = rng.random().intRangeAtMost(u8, 0, width - 1),
            .y = rng.random().intRangeAtMost(u8, 2, height - 1),
            .brightness = rng.random().intRangeAtMost(u8, 0, 2),
        };
    }
    
    fn draw(self: *const Star, writer: anytype) !void {
        moveCursor(self.y, self.x);
        const star_chars = [_][]const u8{ "·", "✦", "★" };
        const star_colors = [_][]const u8{ Colors.dim, "", Colors.bright };
        try writer.print("{s}{s}{s}", .{ 
            star_colors[self.brightness], 
            star_chars[self.brightness],
            Colors.reset 
        });
    }
};

fn drawStarfield(stars: []Star, writer: anytype) !void {
    for (stars) |*star| {
        try star.draw(writer);
    }
}

fn drawHexagonalFrame(writer: anytype, row: u32, col: u32) !void {
    const hex_top = "╱‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾╲";
    const hex_mid = "❬                        ❭";
    const hex_bot = "╲________________________╱";
    
    moveCursor(row, col);
    try writer.print("{s}{s}{s}", .{ Colors.cyan, hex_top, Colors.reset });
    
    moveCursor(row + 1, col);
    try writer.print("{s}{s}{s}", .{ Colors.cyan, hex_mid, Colors.reset });
    
    moveCursor(row + 2, col);
    try writer.print("{s}{s}{s}", .{ Colors.cyan, hex_mid, Colors.reset });
    
    moveCursor(row + 3, col);
    try writer.print("{s}{s}{s}", .{ Colors.cyan, hex_bot, Colors.reset });
}

fn drawOrbitals(writer: anytype, frame: u32, center_row: u32, center_col: u32) !void {
    const radius = 25;
    const orbital_chars = [_][]const u8{ "◦", "○", "●", "◉" };
    
    // Calculate positions for 3 orbitals
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const angle = @as(f32, @floatFromInt(frame + i * 120)) * 0.05;
        const x = @cos(angle) * @as(f32, @floatFromInt(radius));
        const y = @sin(angle) * @as(f32, @floatFromInt(radius)) * 0.3; // Elliptical orbit
        
        const screen_x = @as(i32, @intCast(center_col)) + @as(i32, @intFromFloat(x));
        const screen_y = @as(i32, @intCast(center_row)) + @as(i32, @intFromFloat(y));
        
        if (screen_x > 0 and screen_y > 0 and screen_y < 24) {
            moveCursor(@intCast(screen_y), @intCast(screen_x));
            try writer.print("{s}{s}{s}", .{ 
                Colors.bright_blue, 
                orbital_chars[(frame / 10 + i) % 4],
                Colors.reset 
            });
        }
    }
}

fn drawAlienControls(writer: anytype, row: u32) !void {
    const controls = "⟨◉⟩ INITIATE ｜ ⟨◈⟩ NULLIFY ｜ ⟨◬⟩ TERMINATE";
    
    moveCursor(row, 16);
    try writer.print("{s}{s}{s}", .{ Colors.cyan, controls, Colors.reset });
}

const RawMode = struct {
    original: switch (builtin.os.tag) {
        .macos, .linux, .freebsd, .netbsd, .dragonfly, .openbsd => std.c.termios,
        .windows => void,
        else => void,
    },
    
    fn enable() !RawMode {
        switch (builtin.os.tag) {
            .macos, .linux, .freebsd, .netbsd, .dragonfly, .openbsd => {
                const stdin_fd = io.getStdIn().handle;
                
                // Check if stdin is a TTY
                if (!std.posix.isatty(stdin_fd)) {
                    return RawMode{ .original = undefined };
                }
                
                const original = try std.posix.tcgetattr(stdin_fd);
                
                var raw = original;
                // Disable canonical mode, echo, and signals
                raw.lflag.ECHO = false;
                raw.lflag.ICANON = false;
                raw.lflag.ISIG = false;
                raw.lflag.IEXTEN = false;
                
                // Disable input processing
                raw.iflag.IXON = false;
                raw.iflag.ICRNL = false;
                raw.iflag.BRKINT = false;
                raw.iflag.INPCK = false;
                raw.iflag.ISTRIP = false;
                
                // Set minimum characters and timeout
                raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
                raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;
                
                try std.posix.tcsetattr(stdin_fd, .NOW, raw);
                
                return RawMode{ .original = original };
            },
            .windows => {
                // Windows doesn't need raw mode for basic input
                return RawMode{ .original = {} };
            },
            else => {
                return RawMode{ .original = {} };
            },
        }
    }
    
    fn disable(self: *const RawMode) void {
        switch (builtin.os.tag) {
            .macos, .linux, .freebsd, .netbsd, .dragonfly, .openbsd => {
                const stdin_fd = io.getStdIn().handle;
                if (std.posix.isatty(stdin_fd)) {
                    std.posix.tcsetattr(stdin_fd, .NOW, self.original) catch {};
                }
            },
            else => {},
        }
    }
};

fn restoreTerminal() void {
    showCursor();
    clearScreen();
}

pub fn main() !void {
    const stdout = io.getStdOut().writer();
    const stdin = io.getStdIn().reader();
    
    var stopwatch = Stopwatch{};
    
    // Enable raw mode for keyboard input
    const raw_mode = try RawMode.enable();
    defer raw_mode.disable();
    
    clearScreen();
    hideCursor();
    defer restoreTerminal();
    
    // Initialize random number generator for stars
    var prng = std.Random.DefaultPrng.init(@intCast(time.milliTimestamp()));
    
    // Create starfield
    var stars: [50]Star = undefined;
    for (&stars) |*star| {
        star.* = Star.new(&prng, 80, 24);
    }
    
    var running = true;
    var buffer: [1]u8 = undefined;
    var frame: u32 = 0;
    
    while (running) {
        clearScreen();
        
        // Draw starfield
        try drawStarfield(&stars, stdout);
        
        // Draw title
        moveCursor(2, 25);
        try stdout.print("{s}{s}◇ CHRONOS STATION ◇{s}", .{ Colors.bright, Colors.cyan, Colors.reset });
        
        // Draw hexagonal frame
        try drawHexagonalFrame(stdout, 8, 26);
        
        const elapsed = stopwatch.getElapsedTime();
        const formatted = formatTime(elapsed);
        
        // Draw time in holographic blue
        moveCursor(10, 30);
        try stdout.print("{s}{s}{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}{s}", .{
            Colors.bright,
            Colors.bright_blue,
            formatted.hours,
            formatted.minutes,
            formatted.seconds,
            formatted.millis,
            Colors.reset,
        });
        
        // Draw status
        moveCursor(14, 35);
        if (stopwatch.is_running) {
            try stdout.print("{s}{s}◆ ACTIVE ◆{s}", .{ Colors.blink, Colors.bright_blue, Colors.reset });
        } else {
            try stdout.print("{s}◇ STANDBY ◇{s}", .{ Colors.dim, Colors.reset });
        }
        
        // Draw rotating orbitals
        try drawOrbitals(stdout, frame, 11, 40);
        
        // Draw alien controls
        try drawAlienControls(stdout, 20);
        
        // Animate some stars
        if (frame % 5 == 0) {
            for (&stars, 0..) |*star, i| {
                if (i % 3 == frame % 3) {
                    star.brightness = (star.brightness + 1) % 3;
                }
            }
        }
        
        frame = (frame + 1) % 360;
        
        // Check for keyboard input
        if (builtin.os.tag == .windows) {
            // Windows doesn't support poll, use blocking read with timeout
            const bytes_read = stdin.read(&buffer) catch 0;
            if (bytes_read > 0) {
                const key = buffer[0];
                
                switch (key) {
                    ' ' => {
                        if (stopwatch.is_running) {
                            stopwatch.stop();
                        } else {
                            stopwatch.start();
                        }
                    },
                    'r', 'R' => {
                        stopwatch.reset();
                    },
                    'q', 'Q' => {
                        running = false;
                    },
                    else => {},
                }
            }
            time.sleep(50 * time.ns_per_ms);
        } else {
            // Unix-like systems use poll
            var fds = [_]std.posix.pollfd{
                .{
                    .fd = io.getStdIn().handle,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };
            
            // Poll with 50ms timeout
            const poll_result = try std.posix.poll(&fds, 50);
            
            if (poll_result > 0 and (fds[0].revents & std.posix.POLL.IN) != 0) {
                const bytes_read = try stdin.read(&buffer);
                if (bytes_read > 0) {
                    const key = buffer[0];
                    
                    switch (key) {
                        ' ' => {
                            if (stopwatch.is_running) {
                                stopwatch.stop();
                            } else {
                                stopwatch.start();
                            }
                        },
                        'r', 'R' => {
                            stopwatch.reset();
                        },
                        'q', 'Q' => {
                            running = false;
                        },
                        else => {},
                    }
                }
            }
        }
    }
}