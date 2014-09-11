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

/** Recording that iterates over events recorded as binary data by a Recorder.
 *
 * Used for replaying recordings recorded during current game and for serializing
 * recordings for writing to YAML.
 */
final class BinaryRecording(Input): Recording!Input
{
private:
    alias Event = Recorder!Input.Event;

    import std.container;

    // Raw binary recording.
    Array!ubyte data_;

    // Range to the part of data_ for the remainder of the BinaryRecording range.
    data_.Range dataRange_;

package:
nothrow:
    /** Construct a BinaryRecording from recorded data.
     *
     * Only InputDevice code can construct a BinaryRecording.
     *
     * Params:
     *
     * data = Recorded data.
     */
    this(ref Array!ubyte data)
        @trusted //pure @nogc
    {
        data_      = data.dup.assumeWontThrow;
        dataRange_ = data_[].assumeWontThrow;
        updateFront();
    }

protected:
    override void popFront() @trusted //pure @nogc
    {
        assert(!empty, "Calling popFront() on an empty range");

        // Skip current Event in binary data, and also skip BaseState after Change events.
        const event = cast(Event)dataRange_.front;
        if(event == Event.NoChange) { dataRange_.popFront(); }
        else
        {
            dataRange_.popFront();
            delegate
            {
                dataRange_ = dataRange_[Input.BaseState.sizeof .. $];
            }().assumeWontThrow;
        }
        updateFront();
    }

    override bool empty() @safe pure const @nogc
    {
        return dataRange_.empty;
    }

private:
    /// Update front of the range (inputState_). Called by constructor/popFront().
    void updateFront() @trusted
    {
        if(empty) { return; }
        // If current event is Change, read BaseState from binary data.
        const event = cast(Event)dataRange_.front;
        if(event != Event.NoChange)
        {
            assert(event == Event.Change, "unknown recorder event ID");
            // `1` skips the event ID.
            inputState_ = *cast(Input.BaseState*)&(dataRange_[1]);
        }
    }
}

/// Recording that reads recorded input from YAML.
final class YAMLRecording(Input): Recording!Input
{
private:
    alias Event = Recorder!Input.Event;

    // Currently GC-based, but shouldn't be an issue as recordings are mostly for
    // debugging, and even otherwise should be used infrequently (e.g. once per game,
    // as opposed to once per some fixed time period)

    // Recording events (Change, NoChange).
    Event[] events_;
    // States of recorded data to change to for every Change event in events_.
    Input.BaseState[] states_;

package:
    /** Construct a YAMLRecording from a YAML node (produced by toYAML(Recording)).
     *
     * Throws:
     *
     * ConvException if any value in the YAML has unexpected format.
     * YAMLException if the YAML has unexpected layout.
     */
    this(YAMLNode data) @trusted
    {
        foreach(string key, ref YAMLNode value; data)
        {
            events_.assumeSafeAppend;
            events_ ~= to!Event(key);
            if(events_.back == Event.NoChange) { continue; }
            states_ ~= Input.BaseState.fromYAML(value);
            states_.assumeSafeAppend;
        }
        updateFront();
    }

protected:
@safe pure nothrow @nogc:
    override void popFront()
    {
        assert(!empty, "Calling popFront() on an empty range");

        const event = events_.front;
        if(event != Event.NoChange)
        {
            assert(event == Event.Change, "unknown recorder event ID");
            states_.popFront();
        }
        events_.popFront();
        updateFront();
    }

    override bool empty() const { return events_.empty; }

private:
    /// Update front of the range (inputState_). Called by constructor/popFront().
    void updateFront()
    {
        if(empty) { return; }
        const event = events_.front;
        if(event != Event.NoChange)
        {
            assert(event == Event.Change, "unknown recorder event ID");
            inputState_ = states_.front;
        }
    }
}
