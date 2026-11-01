const std = @import("std");
const fmt = std.fmt;
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const Io = std.Io;
const Allocator = mem.Allocator;

const fsrs = @import("zig-fsrs");
const vaxis = @import("vaxis");

const log = std.log.scoped(.main);

const TableItem = struct {
    index: usize,
    due: std.Io.Timestamp,
    state: fsrs.models.State,
    last_review: std.Io.Timestamp,
    stability: f32,
    difficulty: f32,
    elapsed_days: i64,
    scheduled_days: i64,
    reps: i64,
    lapses: i64,

    fn fromCardWithIndex(card: fsrs.Card, index: usize) TableItem {
        return TableItem{
            .index = index,
            .due = card.due,
            .state = card.state,
            .last_review = card.last_review,
            .stability = card.stability,
            .difficulty = card.difficulty,
            .elapsed_days = card.elapsed_days,
            .scheduled_days = card.scheduled_days,
            .reps = card.reps,
            .lapses = card.lapses,
        };
    }
};

fn handleRateCard(f: *fsrs.Fsrs, card_history: *std.ArrayList(fsrs.Card), table_list: *std.ArrayList(TableItem), rating: fsrs.Rating) !void {
    const last_card = card_history.last().?;
    const s = f.schedule(last_card, last_card.due);
    const new_card = s.select(rating).card;
    try card_history.append(new_card);
    try table_list.append(TableItem.fromCardWithIndex(new_card, table_list.items.len));
}

const CardManager = struct {
    gpa: Allocator,
    f: fsrs.Fsrs = .init(.{}),
    card_history: std.ArrayList(fsrs.Card) = .empty,
    table_list: std.ArrayList(TableItem) = .empty,

    pub fn handleRateCard(self: *CardManager, rating: fsrs.Rating) Allocator.Error!void {
        const last_card = self.card_history.last().?;
        const s = self.f.schedule(last_card, last_card.due);
        const new_card = s.select(rating).card;
        try self.card_history.append(self.gpa, new_card);
        try self.table_list.append(self.gpa, .fromCardWithIndex(new_card, self.table_list.items.len));
    }

    pub fn init(io: Io, allocator: Allocator) Allocator.Error!CardManager {
        var result: CardManager = .{ .gpa = allocator };
        errdefer result.deinit();
        const init_card: fsrs.Card = .init(io);
        try result.card_history.append(result.gpa, init_card);
        try result.table_list.append(result.gpa, .fromCardWithIndex(init_card, 0));
        return result;
    }

    pub fn deinit(self: *CardManager) void {
        self.card_history.deinit(self.gpa);
        self.table_list.deinit(self.gpa);
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var manager: CardManager = try .init(io, alloc);
    defer manager.deinit();

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &buffer);
    defer tty.deinit();

    var vx = try vaxis.init(io, alloc, init.environ_map, .{});
    defer vx.deinit(alloc, tty.writer());

    var loop: vaxis.Loop(union(enum) {
        key_press: vaxis.Key,
        winsize: vaxis.Winsize,
    }) = .init(io, &tty, &vx);

    try loop.start();
    defer loop.stop();
    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromNanoseconds(1));

    // Colors
    const selected_bg: vaxis.Cell.Color = .{ .rgb = .{ 64, 128, 255 } };
    const active_bg: vaxis.Cell.Color = .{ .rgb = .{ 64, 128, 255 } };
    const other_bg: vaxis.Cell.Color = .{ .rgb = .{ 32, 32, 48 } };

    const title_logo = vaxis.Cell.Segment{
        .text = "zig-fsrs\n",
        .style = .{
            .bg = other_bg,
        },
    };
    const title_info = vaxis.Cell.Segment{
        .text = "Press 1-4 to rate the card.\n",
        .style = .{
            .bg = other_bg,
        },
    };
    const title_ratings = vaxis.Cell.Segment{
        .text = "1: again  2: hard  3: good  4: easy\n",
        .style = .{
            .fg = .{ .rgb = .{ 255, 255, 255 } },
            .bg = .{ .rgb = .{ 0, 0, 0 } },
        },
    };
    var title_segs = [_]vaxis.Cell.Segment{ title_logo, title_info, title_ratings };

    var keys = [_]vaxis.Cell.Segment{.{
        .text = "k: up\nj: down\nh: left\nl: right\nctrl + C: exit",
        .style = .{
            .fg = .{ .rgb = .{ 128, 128, 128 } },
            .bg = other_bg,
        },
    }};

    // Table Context
    var demo_tbl: vaxis.widgets.Table.TableContext = .{
        .selected_bg = selected_bg,
        .active_bg = active_bg,
    };

    while (true) {
        // Create an Arena Allocator for easy allocations on each Event.
        var event_arena = heap.ArenaAllocator.init(alloc);
        defer event_arena.deinit();
        const event_alloc = event_arena.allocator();
        const event = try loop.nextEvent();

        switch (event) {
            .key_press => |key| {
                // Close the Program
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                }

                for ("1234") |char| {
                    if (key.matches(char, .{})) {
                        try manager.handleRateCard(@fromBackingInt(@intCast(char - '0')));
                        demo_tbl.row = @intCast(manager.card_history.items.len - 1);
                        break;
                    }
                }

                // Change Row
                if (key.matchesAny(&.{ vaxis.Key.up, 'k' }, .{})) demo_tbl.row -|= 1;
                if (key.matchesAny(&.{ vaxis.Key.down, 'j' }, .{})) demo_tbl.row +|= 1;
                // Change Column
                if (key.matchesAny(&.{ vaxis.Key.left, 'h' }, .{})) demo_tbl.col -|= 1;
                if (key.matchesAny(&.{ vaxis.Key.right, 'l' }, .{})) demo_tbl.col +|= 1;
            },
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
            //else => {},
        }

        // Sections
        // - Window
        const win = vx.window();
        win.clear();

        // - Top left
        const top_left_bar = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = win.width / 3,
            .height = 5,
        });
        top_left_bar.fill(.{ .style = .{
            .bg = other_bg,
        } });
        _ = top_left_bar.print(keys[0..], .{ .wrap = .word });

        // - Top middle
        const top_middle_bar = win.child(.{
            .x_off = win.width / 3,
            .y_off = 0,
            .width = win.width / 3,
            .height = 5,
        });
        top_middle_bar.fill(.{ .style = .{
            .bg = other_bg,
        } });
        const logo_bar = vaxis.widgets.alignment.center(top_middle_bar, 42, 3);
        _ = logo_bar.print(title_segs[0..], .{ .wrap = .word });

        // - Top right
        const top_right_bar = win.child(.{
            .x_off = win.width / 3 * 2,
            .y_off = 0,
            .width = win.width / 3,
            .height = 5,
        });
        top_right_bar.fill(.{ .style = .{
            .bg = other_bg,
        } });

        // - Middle
        const middle_bar = win.child(.{
            .x_off = 0,
            .y_off = 5,
            .width = win.width,
            .height = win.height - top_middle_bar.height,
        });

        if (manager.card_history.items.len > 0) {
            demo_tbl.active = true;
            demo_tbl.header_names = .{ .custom = &.{
                "index", "due", "state", "last review", "stability", "difficulty", "elapsed days", "scheduled days", "reps", "lapses",
            } };
            try vaxis.widgets.Table.drawTable(
                event_alloc,
                middle_bar,
                manager.table_list,
                &demo_tbl,
            );
        }

        // Render the screen
        try vx.render(tty.writer());
    }
}
