const std = @import("std");

const models = @import("models.zig");
const Parameters = models.Parameters;
const Card = models.Card;
const SchedulingCards = models.SchedulingCards;
const ScheduledCards = models.ScheduledCards;
const Rating = models.Rating;

const Self = @This();

params: Parameters,

pub fn init(params: Parameters) Self {
    return .{
        .params = params,
    };
}

pub fn schedule(self: Self, card: Card, now: std.Io.Timestamp) ScheduledCards {
    const minute = 60;
    const day = 24 * 60 * 60;
    var c = card;

    c.elapsed_days = if (c.state == .new)
        0
    else
        @divFloor(c.last_review.durationTo(now).toSeconds(), day);

    c.last_review = now;
    c.reps += 1;
    var s = SchedulingCards.init(c);
    s.updateState(card.state);

    switch (card.state) {
        .new => {
            s.again.stability = self.initStability(.again);
            s.again.difficulty = self.initDifficulty(.again);
            s.hard.stability = self.initStability(.hard);
            s.hard.difficulty = self.initDifficulty(.hard);
            s.good.stability = self.initStability(.good);
            s.good.difficulty = self.initDifficulty(.good);
            s.easy.stability = self.initStability(.easy);
            s.easy.difficulty = self.initDifficulty(.easy);

            const easy_interval = self.nextInterval(s.easy.stability);

            s.again.due = now.addDuration(.fromSeconds(1 * minute));
            s.hard.due = now.addDuration(.fromSeconds(5 * minute));
            s.good.due = now.addDuration(.fromSeconds(10 * minute));
            s.easy.due = now.addDuration(.fromSeconds(easy_interval * day));
            s.easy.scheduled_days = easy_interval;
        },
        .learning, .relearning => {
            const good_interval = self.nextInterval(s.good.stability);
            const easy_interval = @max(good_interval + 1, self.nextInterval(s.easy.stability));

            s.again.scheduled_days = 0;
            s.again.due = now.addDuration(.fromSeconds(5 * minute));
            s.hard.scheduled_days = 0;
            s.hard.due = now.addDuration(.fromSeconds(10 * minute));
            s.good.scheduled_days = good_interval;
            s.good.due = now.addDuration(.fromSeconds(good_interval * day));
            s.easy.scheduled_days = easy_interval;
            s.easy.due = now.addDuration(.fromSeconds(easy_interval * day));
        },
        .review => {
            s.again.stability = self.nextForgetStability(&c);
            s.again.difficulty = self.nextDifficulty(&c, .again);
            s.hard.stability = self.nextRecallStability(&c, .hard);
            s.hard.difficulty = self.nextDifficulty(&c, .hard);
            s.good.stability = self.nextRecallStability(&c, .good);
            s.good.difficulty = self.nextDifficulty(&c, .good);
            s.easy.stability = self.nextRecallStability(&c, .easy);
            s.easy.difficulty = self.nextDifficulty(&c, .easy);

            var hard_interval = self.nextInterval(s.hard.stability);
            var good_interval = self.nextInterval(s.good.stability);
            var easy_interval = self.nextInterval(s.easy.stability);

            hard_interval = @min(hard_interval, good_interval);
            good_interval = @max(good_interval, hard_interval + 1);
            easy_interval = @max(easy_interval, good_interval + 1);

            s.again.scheduled_days = 0;
            s.again.due = now.addDuration(.fromSeconds(5 * minute));
            s.hard.scheduled_days = hard_interval;
            s.hard.due = now.addDuration(.fromSeconds(hard_interval * day));
            s.good.scheduled_days = good_interval;
            s.good.due = now.addDuration(.fromSeconds(good_interval * day));
            s.easy.scheduled_days = easy_interval;
            s.easy.due = now.addDuration(.fromSeconds(easy_interval * day));
        },
    }

    return s.toScheduledCards(now);
}

fn initStability(self: Self, rating: Rating) f32 {
    return @max(self.params.w[@backingInt(rating) - 1], 0.1);
}

fn initDifficulty(self: Self, rating: Rating) f32 {
    const difficulty = @mulAdd(
        f32,
        self.params.w[5],
        -(@as(f32, @floatFromInt(@backingInt(rating))) - 3.0),
        self.params.w[4],
    );

    return @min(10, @max(1, difficulty));
}

fn forgettingCurve(elapsed_days: i64, stability: f32) f32 {
    return std.math.pow(
        f32,
        1.0 + Parameters.FACTOR * @as(f32, @floatFromInt(elapsed_days)) / stability,
        Parameters.DECAY,
    );
}

fn meanReversion(self: Self, initial: f32, current: f32) f32 {
    return @mulAdd(
        f32,
        self.params.w[7],
        initial,
        (1.0 - self.params.w[7]) * current,
    );
}

fn nextInterval(self: Self, stability: f32) i64 {
    const next_interval = @as(i32, @intFromFloat(@round(
        stability / Parameters.FACTOR *
            (std.math.pow(
                f32,
                self.params.request_retention,
                1.0 / Parameters.DECAY,
            ) - 1.0),
    )));

    return @max(1, @min(self.params.maximum_interval, next_interval));
}

fn nextForgetStability(self: Self, card: *const Card) f32 {
    const retrievability = forgettingCurve(card.elapsed_days, card.stability);
    return self.params.w[11] *
        std.math.pow(f32, card.difficulty, -self.params.w[12]) *
        (std.math.pow(f32, card.stability + 1.0, self.params.w[13]) - 1.0) *
        std.math.exp((1.0 - retrievability) * self.params.w[14]);
}

fn nextRecallStability(self: Self, card: *const Card, rating: Rating) f32 {
    const modifier = switch (rating) {
        .hard => self.params.w[15],
        .easy => self.params.w[16],
        else => 1.0,
    };

    const retrievability = forgettingCurve(card.elapsed_days, card.stability);
    return card.stability *
        @mulAdd(
            f32,
            std.math.exp(self.params.w[8]) *
                (11.0 - card.difficulty) *
                std.math.pow(f32, card.stability, -self.params.w[9]) *
                std.math.expm1((1.0 - retrievability) * self.params.w[10]),
            modifier,
            1.0,
        );
}

fn nextDifficulty(self: Self, card: *const Card, rating: Rating) f32 {
    const difficulty = @mulAdd(
        f32,
        self.params.w[6],
        -(@as(f32, @floatFromInt(@backingInt(rating))) - 3.0),
        card.difficulty,
    );

    return @min(10.0, @max(1.0, self.meanReversion(self.params.w[4], difficulty)));
}
