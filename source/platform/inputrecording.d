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
