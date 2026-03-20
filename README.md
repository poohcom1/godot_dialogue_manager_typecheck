# Dialogue Manager - Type Checker

An addon to an addon--a type checker module for [Nathan Hoad's Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager).

![Example usage as tools](.github/assets/tool%20example.png)

![Output example](.github/assets/error%20output.png)

Mirror of my local project--I won't be maintaining much, but feel free to open a PR for increase coverage.

## Installation

Version number tracks the base addon's version. If the base addon's version is higher, it may or may not work with that version.

1. Download or clone the repo.
2. Copy `addons/dialogue_manager_type_check` to your project's addon folder.
3. Make sure dialogue_manager is already activated.
4. Activate "Dialogue Manager Type Checker" in the plugins.

## Features

- Adds an editor tool at `Project > Tools > Dialogue > Check Type` to analyze the type correctness of a dialogue file.
- [Planned] A script that can be used in CI to verify all dialogue files in a project.

## Type Coverage

| Case                       | Example                         | Covered        | Comment                                                        |
| -------------------------- | ------------------------------- | -------------- | -------------------------------------------------------------- |
| Top-level expressions      | `do global_function()`          | yes            | Inferred from `using` or `state_autoload_shortcuts` in setting |
| Extra auto-complete source | `do extra_function()`           | false-positive | Inferred from `extra_auto_complete_script_sources` in setting  |
| Nested expression          | `do Autoload.function()`        | yes            |                                                                |
| if statements              | `if Autoload.member`            | yes            |                                                                |
| set statements             | `set Autoload.member = 1`       | yes            |                                                                |
| C# async methods           | `do DotnetAutoload.AsyncTask()` | yes            |                                                                |
| Enums                      | `Autoload.Enum.A`               | false-positive |                                                                |
| Static                     | `Autoload.Class.static_func()`  | false-positive |                                                                |
| Nested expressions         | `do function(Autoload.member)`  | ignore         |                                                                |
| Function signature         | `do function(1, "123")`         | ignored        | Planned                                                        |
