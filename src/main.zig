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
                std.posix.tcsetattr(stdin_fd, .NOW, self.original) catch {};
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
    
    var running = true;
    var buffer: [1]u8 = undefined;
    
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