===================================
Tharsis-Game: Test game for Tharsis
===================================

This is a very early work in progress and is not usable.

(Note: this is not a *real game*. It's a testbed for Tharsis (`core
<https://github.com/kiith-sa/tharsis-core>`_, `full
<https://github.com/kiith-sa/tharsis-full>`_) features.)



========
Controls
========

========================== =========================================================
``W``, ``A``, ``S``, ``D`` Move camera
``RMB`` drag               Move camera quickly
``Wheel``                  Zoom camera
``LMB``                    Select/deselect entities
``LMB`` drag               Select entities in rectangle area
``Ctrl`` + ``RMB``         Attack a point with selected entities
``RMB``                    Move to point with selected entities
``ESC``                    Quit
``F1``                     Print current diagnostics
``F2``                     Print current load
``F3``                     Start/stop recording demo input (``mouse_keyboard.yaml``)
``F4``                     Launch Despiker
``F5``                     Print PrototypeManager error log
``1``                      Draw everything fully
``2``                      Draw everything as points
``3``                      Don't draw anything
``S-Q``                    Scheduling: LPT
``S-W``                    Scheduling: Dumb (equal process count per thread)
``S-E``                    Scheduling: Random backtracking (time 400, retries 3)
``S-R``                    Scheduling: Random backtracking (time 800, retries 6)
``S-T``                    Scheduling: Random backtracking (time 1600, retries 9)
========================== =========================================================



=================
Command-line help
=================

.. code::

   Tharsis-game
   Benchmark game for Tharsis
   Copyright (C) 2014 Ferdinand Majerech

   Usage: tharsis-game [--help] <command> [local-options ...]

   Global options:
     --help                     Print this help information.
     --sched-algo               Scheduling algorithm to use. Possible values:
                                Dumb      Equal number of Processes per thread
                                LPT       Longest Processing Time (fast, decent)
                                COMBINE   COMBINE (slightly slower, better)
                                BRUTE     Bruteforce backtracking (extremely slow)
                                RBt400r3  Random backtrack, time=400, attempts=3
                                RBt800r6  Random backtrack, time=800, attempts=6
                                RBt1200r9 Random backtrack, time=1200, attempts=9
                                Default: LPT
     --threads=<count>          Number of threads to run Tharsis processes in.
                                If 0, Tharsis automatically determines the number
                                of threads to use.
                                Default: 0
     --headless                 If specified, tharsis-game will run without any
                                graphics (without even opening a window)
     --width=<pixels>           Window width.
                                Default: 1024
     --height=<pixels>          Window height.
                                Default: 768


   Commands:
     demo                       Play a pre-recorded demo, executing tharsis-game
                                with recorded keyboard/mouse input. Exactly one
                                local argument (demo file name) must be specified.
       Local options:
         --direct               Allow direct mouse/keyboard input to pass through
                                along with the recorded demo input (allowing the
                                user to affect the demo as it runs)
         --quitWhenDone         Quit once the all recorded input is replayed (once
                                the demo ends).
                                By default, the game will continue to run after
                                demo is replayed.

       Local arguments:
         <filename>             Name of the recorded input file to execute.
   -------------------------------------------------------------------------------
