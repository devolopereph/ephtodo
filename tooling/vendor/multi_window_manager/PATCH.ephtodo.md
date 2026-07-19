# Local patch of multi_window_manager 1.3.0 (ephtodo Phase 0)

This directory is a vendored copy of `multi_window_manager` 1.3.0 from pub.dev
(upstream: https://github.com/vvlad-islavs/multi-window-manager), consumed via
`dependency_overrides` in `tooling/phase0/pubspec.yaml`.

## Why

`MultiWindowManager::createWindow` in `windows/multi_window_manager.cpp`
prepended the new window id to the caller's window arguments using
`std::merge`:

```cpp
std::vector<std::string> v1 = {std::to_string(windowId)};
std::vector<std::string> dst;
std::merge(v1.begin(), v1.end(), args.begin(), args.end(),
           std::back_inserter(dst));
```

`std::merge` requires **both** input ranges to already be sorted. Arbitrary
window arguments (e.g. `["sticky", "{...json...}", "automation"]`) are not
sorted, so MSVC Debug builds abort with:

```
Debug Assertion Failed!  Expression: sequence not ordered  (xutility:1814)
```

before the secondary window's Flutter engine ever starts. Release builds
"work" only by accident (unchecked UB) and can still reorder the arguments,
breaking positional argument parsing in the secondary window.

## What changed

One site in `windows/multi_window_manager.cpp` (`createWindow`), replacing the
merge with plain concatenation, which is what upstream intended:

```cpp
std::vector<std::string> dst;
dst.reserve(args.size() + 1);
dst.push_back(std::to_string(windowId));
dst.insert(dst.end(), args.begin(), args.end());
```

No other files were modified. `build/`, `example/`, `test/` and media files
were dropped from the vendored copy to keep the tree small.
