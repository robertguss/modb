

**2026-11-14, exploring both pictures.** Robert had the first picture in mind, found the second intriguing, and asked to stay here and explore before choosing. Observations and ideas put to him:

- A Mo service is already a small version of the second picture: one typed state, tools that are functions from the old state to a new state and a reply, time passed in as an argument, every call logged (`~/code/mo/services/task-queue/main.mo`). What it lacks to be a database: state larger than memory, finding things without walking everything, questions nobody wrote a tool for, more than one caller, and data shared between programs.
- The pictures meet if the first picture's request language is Mo: an agent sends a small Mo program, and the database checks it and runs it beside the data.
- Ideas: the request is a program; promises as the schema; upgrades as migrations; the log as the permanent truth; a world per agent; simulation built in; shared stores reached through capabilities; and three answers to unplanned questions (scan, indexes the database proposes, a declarative form inside Mo).
