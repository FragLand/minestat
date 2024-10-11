# Contributing to MineStat

## Issue Tracker

https://github.com/FragLand/minestat/issues

## IRC

irc://irc.frag.land:6697/minestat

## Matrix

https://matrix.frag.land/

## Coding Convention

Please follow the existing styling as closely as possible for any code contributions. This will vary by programming language. Here are some general tips:

* Make use of comments to document code when sensible.

* Use spaces and not tabs.

* Indent by 2 spaces.

* Use Allman style for blocks (this is not applicable to Go unfortunately). For example:
   ```c
   int func()
   {
     // ...
   }
   ```
   Rather than K&R style:
   ```c
   int func() {
     // ...
   }
   ```

* Constant names should typically be capitalized. For example:
   ```c
   const double PI = 3.14159;
   ```

* Variable and function names containing multiple words should be separated with an underscore `_`. Use PascalCase for C# method names and camelCase for Java method names. Also use camelCase for C# method parameters and local variables.
