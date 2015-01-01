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
``1``                      Draw everything fully
``2``                      Draw everything as points
``3``                      Don't draw anything
``S-Q``                    Scheduling: LPT 
``S-W``                    Scheduling: Dumb (equal process count per thread)
``S-E``                    Scheduling: Random backtracking (time 400, retries 3)
``S-R``                    Scheduling: Random backtracking (time 800, retries 6)
``S-T``                    Scheduling: Random backtracking (time 1600, retries 9)
========================== =========================================================
