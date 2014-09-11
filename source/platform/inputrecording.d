//          Copyright Ferdinand Majerech 2014.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Code used to handle recording and replaying of InputDevice input.
module platform.inputrecording;


import std.array;
import std.conv;
import std.exception;

import io.yaml;

import platform.inputdevice;

/// Enumerates possible recording states of an InputRecordingDevice.
enum RecordingState
{
    /// The InputRecordingDevice is not recording.
    NotRecording,
    /** The InputRecordingDevice about to start recording.
     *
     * InputRecordingDevice doesn't record the first frame after a startRecording() call
     * to avoid recording the input that caused the recording to start.
     */
    FirstFrame,
    /// The InputRecordingDevice is recording.
    Recording
}

/** Base class for input recordings of specified Input type (Mouse or Keyboard).
 *
 * Input type must define a BaseState type defining all state to be recorded (all input
 * state in Input should be either in BaseState or calculated from BaseState data).
 *
 * Acts as an input range of Input.BaseState.
 */
abstract class Recording(Input)
{
protected:
    // Input for the current frame in the recording.
    Input.BaseState inputState_;

public:
    /// Move to the next frame in the recording.
    void popFront() @safe nothrow;

    /// Get input for the current frame in the recording.
    final ref const(Input.BaseState) front() @safe pure nothrow const @nogc
    {
        return inputState_;
    }

    /// Is the recording at the end? (no more recorded frames of input)
    bool empty() @safe pure nothrow const @nogc;
}

package:

/** Records input of an Input type (Mouse or Keyboard).
 *
 * Input type must define a BaseState type defining all state to be recorded (all input
 * state in Input should be either in BaseState or calculated from BaseState data).
 *
 * Data is recorded by passing a buffer to a Recorder constructor, and repeatedly checking
 * if there's enough space using $(D notEnoughSpace()), recording input using
 * $(D recordFrame()) when there's enough space and dumping or copying $(D recordedData()) 
 * followed by a $(D reset()) when there's not enough space.
 */
struct Recorder(Input)
{
    enum minStorageBytes = Event.sizeof + Input.BaseState.sizeof;
private:
    // Buffer used to store recorded data (as raw bytes).
    ubyte[] storage_;

    // Size of used data in storage_ in bytes.
    size_t used_;

    // Recording event IDs.
    enum Event: ubyte
    {
        // No change in input state since the last frame. Reuse previous state.
        NoChange = 0,
        // Input has changed since the last frame. Rewrite input with new state.
        Change = 1
    }

    // Last recorded state. Used by recordFrame() to determine if the state has changed.
    Input.BaseState lastState_;

    /* True if the recorder has just been constructed/reset and there is no recorded data yet.
     *
     * Forces the first recorded event to be a 'Change' event so we record the initial
     * input state.
     */
    bool start_ = true;

public:
pure nothrow @nogc:
    /** Construct a Recorder with specified storage buffer.
     *
     * Params:
     *
     * storage = Buffer to store recorded data. Must be deallocated *after* the Recorder
     *           is destroyed. Must be at least Recorder!Input.minStorageBytes long.
     */
    this(ubyte[] storage) @safe
    {
        storage_ = storage;
        assert(!notEnoughSpace, "Too little memory passed to Mouse.Recorder constructor");
    }


    /** Record input from a frame (game update).
     *
     * Params:
     *
     * input = Current state of the input (Mouse or Keyboard).
     *
     * Must not be called if notEnoughSpace() is true.
     */
    void recordFrame(const(Input) input) @system
    {
        assert(!notEnoughSpace,
               "Recorder.recordFrame() called even though we need more space.");

        if(lastState_ == input.baseState_ && !start_)
        {
            storage_[used_++] = Event.NoChange;
            return;
        }

        start_ = false;
        storage_[used_++] = Event.Change;
        const size = input.baseState_.sizeof;
        storage_[used_ .. used_ + size] = (cast(ubyte*)(&input.baseState_))[0 .. size];
        lastState_ = input.baseState_;
        used_ += size;
    }

    /** If true, there is not enough space to continue recording. Must be checked by user.
     *
     * Once notEnoughSpace() is true, recordFrame() must not be called and the only way
     * to continue recording is to copy recordedData() elsewhere and reset() the Recorder.
     */
    bool notEnoughSpace() @safe const
    {
        return storage_.length - used_ < minStorageBytes;
    }

    /// Reset the recorder, clearing recorded data and reusing the storage buffer.
    void reset() @safe
    {
        used_      = 0;
        storage_[] = 0;
        start_     = true;
    }

    /// Get the (raw binary) data recorded so far.
    const(ubyte)[] recordedData() @safe const
    {
        return storage_[0 .. used_];
    }
}

