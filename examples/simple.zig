const std = @import("std");
const fsrs = @import("zig-fsrs");
const Card = fsrs.models.Card;

pub fn main(init: std.process.Init) !void {
    var f: fsrs.Fsrs = .init(.{});
    const initial_card: Card = .init(init.io);
    var now: std.Io.Timestamp = .now(init.io, .real);
    var s = f.schedule(initial_card, now);

    // good was selected on new card
    const first_rep = s.select(.good).card;
    now = first_rep.due;

    // good was selected on learning card
    s = f.schedule(first_rep, now);
    const second_rep = s.select(.good).card;
    now = second_rep.due;

    // again was selected on review card
    s = f.schedule(second_rep, now);
    const third_rep = s.select(.again).card;
    now = third_rep.due;

    std.debug.print("initial card:\n{f}\n\n", .{initial_card});
    std.debug.print("after first rep (good):\n{f}\n\n", .{first_rep});
    std.debug.print("after second rep (good):\n{f}\n\n", .{second_rep});
    std.debug.print("after third rep (again):\n{f}\n\n", .{third_rep});
}
