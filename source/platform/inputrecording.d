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

