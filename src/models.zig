const std = @import("std");

pub const State = enum(u2) {
    new = 0,
    learning = 1,
    review = 2,
    relearning = 3,
};

pub const Rating = enum(u3) {
    again = 1,
    hard = 2,
    good = 3,
    easy = 4,
};

pub const Parameters = struct {
    pub const DECAY: f32 = -0.5;
    pub const FACTOR: f32 = 19.0 / 81.0;

    request_retention: f32 = 0.9,
    maximum_interval: i32 = 36500,
    w: [17]f32 = .{ 0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755 },
};

pub const ReviewLog = struct {
    rating: Rating,
    elapsed_days: i64,
    scheduled_days: i64,
    state: State,
    reviewed_date: std.Io.Timestamp,
};

pub const ReviewedCard = struct {
    card: Card,
    review_log: ReviewLog,
};

pub const Card = struct {
    state: State,
    reps: i32,
    lapses: i32,
    stability: f32,
    difficulty: f32,
    elapsed_days: i64,
    scheduled_days: i64,
    due: std.Io.Timestamp,
    last_review: std.Io.Timestamp,

    pub fn init(io: std.Io) Card {
        return .{
            .due = .now(io, .real),
            .stability = 0,
            .difficulty = 0,
            .elapsed_days = 0,
            .scheduled_days = 0,
            .reps = 0,
            .lapses = 0,
            .state = .new,
            .last_review = undefined,
        };
    }

    pub fn format(self: Card, writer: *std.Io.Writer) !void {
        try writer.print(
            \\  state:          {t}
            \\  reps:           {d}
            \\  lapses:         {d}
            \\  stability:      {d}
            \\  difficulty:     {d}
            \\  elapsed days:   {d}
            \\  scheduled days: {d}
            \\  due:            {d}
            \\  last review:    {d}
        , self);
    }
};

pub const ScheduledCards = struct {
    again: ReviewedCard,
    hard: ReviewedCard,
    good: ReviewedCard,
    easy: ReviewedCard,

    const Self = @This();

    pub fn select(self: Self, rating: Rating) ReviewedCard {
        return switch (rating) {
            inline else => |r| @field(self, @tagName(r)),
        };
    }
};

pub const SchedulingCards = struct {
    again: Card,
    hard: Card,
    good: Card,
    easy: Card,

    const Self = @This();

    pub fn init(card: Card) Self {
        return .{
            .again = card,
            .hard = card,
            .good = card,
            .easy = card,
        };
    }

    pub fn updateState(self: *Self, state: State) void {
        switch (state) {
            .new => {
                self.again.state = .learning;
                self.hard.state = .learning;
                self.good.state = .learning;
                self.easy.state = .review;
            },
            .learning, .relearning => {
                self.again.state = state;
                self.hard.state = state;
                self.good.state = .review;
                self.easy.state = .review;
            },
            .review => {
                self.again.state = .relearning;
                self.hard.state = .review;
                self.good.state = .review;
                self.easy.state = .review;
                self.again.lapses += 1;
            },
        }
    }

    pub fn toScheduledCards(self: Self, now: std.Io.Timestamp) ScheduledCards {
        var result: ScheduledCards = undefined;
        inline for (@typeInfo(Rating).@"enum".field_names) |rating| {
            std.debug.assert(@TypeOf(@field(result, rating)) == ReviewedCard);
            const card: Card = @field(self, rating);
            @field(result, rating) = .{
                .card = @field(self, rating),
                .review_log = .{
                    .rating = @field(Rating, rating),
                    .elapsed_days = card.elapsed_days,
                    .scheduled_days = card.scheduled_days,
                    .state = card.state,
                    .reviewed_date = now,
                },
            };
        }
        return result;
    }
};
