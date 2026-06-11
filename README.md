# Forked React Compiler

* this vendors the [React Compiler (Rust port)](https://github.com/react/react/tree/main/compiler) into [`react-compiler/`](./react-compiler)
* patches `Cargo.toml` to make it releasable — published to crates.io as [`nextjs_react_compiler_*`](https://crates.io/crates/nextjs_react_compiler)
* license is "Copyright (c) Meta Platforms, Inc. and affiliates."

## Why this exists

[oxc](https://github.com/oxc-project/oxc) and [Rolldown](https://github.com/rolldown/rolldown) need
the React Compiler Rust port on crates.io, but published crates can't use `git` dependencies — every
dependency must itself be on crates.io. The port lives in
[react/react](https://github.com/react/react/tree/main/compiler) and was never published, so this repo
vendors it, patches the crates to be releasable, and publishes them as `nextjs_react_compiler_*`.

The source is synced over unchanged — the only edits are to `Cargo.toml` files (no code changes).
