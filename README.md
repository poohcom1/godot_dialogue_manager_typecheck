# Dialogue Manager _- Type Checker_

An addon to for addon--a type checker module for Nathan Hoad's <img src="https://raw.githubusercontent.com/nathanhoad/godot_dialogue_manager/refs/heads/main/docs/media/logo.svg" height="16px"> [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager).

![Code edit example](.github/assets/code%20edit%20addon.png)

This is a mirror of the addon on my local project--I won't be maintaining it much or upload it to the asset library, but feel free to open a PR for increased coverage.

## Installation

Version number tracks the base addon's version. If the base addon's version is higher, it may or may not work with that version.

1. Download or clone the repo.
2. Copy `addons/dialogue_manager_type_check` to your project's addon folder.
3. Make sure dialogue_manager is already activated.
4. Activate "Dialogue Manager Type Checker" in the plugins.

## Features

### Menu Tool

Adds an editor tool at `Project > Tools > Dialogue > Check Type` to analyze the type correctness of a dialogue file.

![Example usage as tools](.github/assets/tool%20example.png)

Type errors are printed in the output:

![Output example](.github/assets/error%20output.png)

### CLI

Run the following command to verify all dialogue files in a project:

```sh
godot --headless -d addons/dialogue_manager_type_check/cli/check_all.tscn
```

The commands return a non-zero exit code if errors are found, so you can easily plug this into your CI.

![CLI example](.github/assets/cli.png)

### Editor

Adds highlighting in the dialogue editor. Click on the warning icon in the gutter to see more detail on the type error.

![Code edit example](.github/assets/code%20edit%20addon.png)

## Type Coverage

In general, I use DM with a top-level member access or autoload member access, and rarely with any nested logic. As such, I've focused the coverage for these use-cases. I tried to make the current analyzer as forgiving as possible for nested expressions, but as I want to leave it open to improvement for more in-depth analysis, there may be some false positives (i.e. assumed error). If anyone wants to either (1) implement analysis for these or (2) suppress the analyzer from reporting these as errors, feel free to open a PR.

| Case                       | Example                                                 | Covered        |
| -------------------------- | ------------------------------------------------------- | -------------- |
| Top-level expressions      | `do function() # from using or shortcuts`               | **yes**        |
| Extra auto-complete source | `do function() # from extra auto-complete source`       | false-positive |
| Nested expression          | `do Autoload.function()`                                | **yes**        |
| if statements              | `if Autoload.member`                                    | **yes**        |
| set statements             | `set Autoload.member = 1 # assignment type not checked` | ignored        |
| Function signature         | `do function(1,"123")`                                  | ignored        |
| C# async methods           | `do DotnetAutoload.AsyncTask()`                         | **yes**        |
| Enums                      | `Autoload.Enum.A`                                       | false-positive |
| Static                     | `Autoload.Class.static_func()`                          | false-positive |
| Nested expressions         | `do function(Autoload.member)`                          | ignored        |
| In-line mutation           | `NPC: Hey! [do wait(0.1)]Who are you?`                  | **yes**        |
| Snippets                   | `import "res://snippets.dialogues" as snippets`         | not tested     |
| Built-in types             | `do Autoload.queue_free()`                              | not tested     |
