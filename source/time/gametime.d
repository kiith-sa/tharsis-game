
//          Copyright Ferdinand Majerech 2012-2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Timing of game updates.
module time.gametime;


import std.algorithm;

import time.time;

/** Handles timing of game updates.
 *
 * GameTime ensures that all game logic/physics/etc updates happen with a constant tick.
 *
 * If game updates get too slow, they slow down while the game tick length is preserved,
 * resulting in a gameplay slowdown.
 */
class GameTime
{
private:
    // Time taken by single game update.
    real timeStep_;
    // Time this update started, in game time (i.e; the current game time).
    real gameTime_ = 0.0;
    // Time when timeToUpdate() was last called.
    real lastTimeToUpdate_ = -1.0;
    // Time we're behind in game updates.
    real accumulatedTime_ = 0.0;
    // Game time speed multiplier. Zero means pause (stopped time).
    real timeSpeed_ = 1.0;
    // Number of the current update.
    size_t tickIndex_ = 0;

public:
    /// Construct a GameTime with specified time step (tick length) in seconds.
    this(real timeStep) @safe pure nothrow @nogc
    {
        timeStep_ = timeStep;
    }

    /// Is it time to do the next game update yet?
    bool timeToUpdate() @safe nothrow
    {
        const real time = getTime();
        // First call to timeToUpadte(), results in no update.
        if(lastTimeToUpdate_ < 0) { lastTimeToUpdate_ = time; }

        import gfm.math.funcs;
        // Time since last update() call. 
        // The clamp() avoids rounding errors resulting in negative timeElapsed
        // and slows down the game when there's been too much time since the last
        // update.
        const real timeElapsed = 
            ((time - lastTimeToUpdate_) * timeSpeed_).clamp(0.0L, timeStep_ * 16);
        lastTimeToUpdate_ = time;

        accumulatedTime_ += timeElapsed;
        return accumulatedTime_ >= timeElapsed;
    }

    /// Call after finishing a game update to update game time.
    void finishedUpdate() @safe pure nothrow @nogc 
    {
        ++tickIndex_;
        accumulatedTime_ -= timeStep_;
        gameTime_ += timeStep_;
    }

    /// Get current game time.
    real gameTime() @safe pure nothrow const @nogc { return gameTime_; }

    /// Get current time step (always constant, but kept non-static just in case).
    real timeStep() @safe pure nothrow const @nogc { return timeStep_; }

    /// Get time speed.
    real timeSpeed() @safe pure nothrow const @nogc { return timeSpeed_; }

    /// Set time speed.
    void timeSpeed(const real rhs) @safe pure nothrow @nogc { timeSpeed_ = rhs; }
}

