# BashJS

BashJS is an experimental alternative to running JavaScript on NodeJS. Instead of depending on the Node runtime, the goal is to build a lightweight ecosystem that leverages the existing Bash interpreter.

## Tools

- **BPM (BashJS Package Manager)** – a `npm` replacement for managing BashJS packages
- **Declarative Imports** – specify dependencies that BPM can fetch and install
- **Transpiler** – ability to convert JavaScript modules or npm packages to Bash/BPM format

## Design Approach

The project aims to replicate useful parts of the NodeJS ecosystem using Bash tools:

1. **Package Management** – packages are installed and resolved through BPM, which mirrors `npm` functionality.
2. **Standard Modules** – Bash scripts providing equivalents of Node's `fs`, `path`, etc.
3. **CLI Interpreter** – run BashJS projects directly through the existing Bash shell.
4. **Asynchronous Utilities** – features like background jobs to emulate Node's async model.
5. **Tooling** – scripts to transpile JavaScript to Bash and to run tests.

## Planned Features / TODOs

- `bpm init`, `bpm install` and other commands inspired by `npm`
- Import syntax in Bash to load BPM packages
- Conversion of JavaScript packages to BPM-compatible scripts
- Testing framework for BashJS modules
- Cross-platform support (GNU/Linux, macOS, etc.)
- Documentation and examples

BashJS is a work in progress. Contributions and ideas are welcome.
