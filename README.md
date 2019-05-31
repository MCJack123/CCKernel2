# CCKernel2
A custom shell/kernel environment for ComputerCraft.
## Current Features
* Cooperative multitasking through coroutines
* Native IPC calls
* Process signaling
* Built-in debugger
* Multi-user system
* File permissions
* Device files (/dev)
* Eight virtual terminals
* Built-in logger
* Unix-style file hierarchy
* `os.loadAPI` resolution paths
* Process I/O pipes
* systemd-based init program
* Setup program
## Future Features
* CraftOS-PC graphics mode support in virtual terminals (WIP)
* Updated shell with built-in Lua calling
## Usage
Just clone this repository to your computer, `cd` to the directory, and run `CCKernel2.lua`. On first start, it will ask you to create a new user. Type in a full name (display name), a short name (UNIX name), and a password, and then login with your new user.