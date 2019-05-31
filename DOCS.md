# CCKernel2 Documentation
This file lists every new and changed function in CCKernel2.

## Globals
* *function* loadfile(*string* _sFile\[, *table* _tEnv\]): Loads a lua script from a file. (Override)
  * _sFile: The file to read from
  * _tEnv: The environment table of the new function
  * Returns: A function with the contents of the file, or nil + error string
  * Overriden: Checks for the execute permission on the file; checks for a `--!` (dash-dash-bang) at the top of the file to allow alternate scripts (ex. `--!/usr/bin/cksh.lua`)
* error(\[*string* message\[, *number* level\]\]): Throws an error in a lua script. (Override)
  * message: A message to pass to pcall()
  * level: The number of levels up to trigger at
  * Overridden: Added os.debug_enabled to run a lua shell on error
* *string/nil* read(\[*string* _sReplaceChar\[, *table* _tHistory\[, *function* _fnComplete\[, *string*_sDefault\]\]\]\]): Reads a line of text from the user or text from a pipe. (Override)
  * _sReplaceChar: A character to replace each inputted character with
  * _tHistory: A list of options in the history
  * _fnComplete: A function to complete the current word
  * _sDefault: The default text to return
  * Returns: The text typed into the terminal or the text in a pipe, or nil if there's no more data in the pipe or the user presses Alt-D
  * Overridden: Added UNIX input shortcuts, added pipe input

## Events
* process_complete: Sent when a child process completes.
  * *number*: The PID of the child
  * *boolean*: Whether the process was successful (always false right now)

## APIs

### bit
* *boolean* bit.bmask(*number* a, *number* m): Checks if a number matches a bitmask.
  * a: The number to check
  * m: The mask to check
  * Returns: Whether the mask matches ((a & m) == m)

### CCLog
See [the official CCLog reference](https://cckit.readthedocs.io/en/latest/CCLog/) for more information.

### fs
All of the default fs functions have been overridden to add permission checks and mounts. If the current user doesn't have adequate permissions to access the files, an error will be thrown from the fs call.
* *nil* fs.linkDir(*string* from, *string* to): Creates a \[temporary\] directory link from a folder.
  * from: The source directory
  * to: The link directory
* *nil* fs.unlinkDir(*string* to): Unlinks a previously linked directory.
  * to: The link to remove
* *number* fs.getPermissions(*string* path\[, *number* uid\]): Returns the permissions for a path.
  * path: The path to check
  * uid: The UID to check for, defaults to the current user
  * Returns: The permissions allowed for the file/directory (see `permissions`)
* *nil* fs.setPermissions(*string* path, \[ *number* uid\], *number* perm): Sets the permissions for a path, if the current user is the owner or root.
  * path: The path to set permissions for
  * uid: The UID to set for, defaults to the current user
  * perm: The permissions to set
* *nil* fs.addPermissions(*string* path, \[ *number* uid\], *number* perm): Adds (or retains) permissions for a path, if the current user is the owner or root.
  * path: The path to set permissions for
  * uid: The UID to set for, defaults to the current user
  * perm: The permissions to add
* *nil* fs.removePermissions(*string* path, \[ *number* uid\], *number* perm): Removes permissions for a path, if the current user is the owner or root.
  * path: The path to set permissions for
  * uid: The UID to set for, defaults to the current user
  * perm: The permissions to remove
* *number* fs.getOwner(*string* path): Returns the owner of a path.
  * path: The path to check
  * Returns: The UID of the owner
* *nil* fs.setOwner(*string* path\[, *number* uid\]): Sets the owner of a path, if the current user is the owner or root.
  * path: The path to set the owner of
  * uid: The UID of the new owner, defaults to the current user
* *nil* fs.mount(*string* path, *table* mount): Mounts a filesystem to a path. (Requires root)
  * path: The path of the new mount
  * mount: The new filesystem to mount
* *nil* fs.unmount(*string* path): Unmounts a filesystem. (Requires root)
  * path: The path to the mount
* *boolean* fs.hasPermissions(*string* path\[, *number* uid\], *number* perms): Returns whether a user has certain permissions on a path.
  * path: The path to check
  * uid: The UID of the user, defaults to the current user
  * perms: The permissions to check
  * Returns: Whether the user has all of the permissions in `perms`
* *table* fs.mounts(): Returns a copy of the list of mounts, including links.

### kernel
* *number* kernel.exec(*string* path\[, *table* env\], ...): Starts a new process from a file in parallel.
  * path: The path to the file
  * env: Optional, the environment table of the new program (otherwise, ...)
  * ...: Any arguments to pass to the file
  * Returns: The PID of the new process
* *number* kernel.fork(*string* name, *function* func[, *table* env], ...): Starts a new process from a function in parallel.
  * name: The name of the process for `ps`
  * func: The function to run
  * env: Optional, the environment table of the new program (otherwise, ...)
  * ...: Any arguments to pass to the function
  * Returns: The PID of the new process
* *nil* kernel.kill(*number* pid, *number* sig): Sends a signal to a process.
  * pid: The PID to recieve the signal
  * sig: The signal to send (see `signal`)
* *nil* kernel.signal(*number* sig, *function* handler): Sets a signal handler for a signal.
  * sig: The signal to handle
  * handler: The function to call
* *nil* kernel.send(*number* pid, *string* ev, ...): Sends an event to a process.
  * pid: The PID to send to
  * ev: The event to send
  * ...: Any arguments to send in the event
* *nil* kernel.broadcast(*string* ev, ...): Sends an event to all processes.
  * ev: The event to send
  * ...: Any arguments to send in the event
* *number* kernel.getPID(): Returns the current process ID (PID).
* *nil* kernel.chvt(*number* id): Changes the currently active virtual terminal.
* *number* kernel.getvt(): Returns the currently active virtual terminal.
* *number* kernel.getArgs(): Returns the arguments passed to the kernel.
* *nil* kernel.setProcessProperty(*number* pid, *string* k, *any* v): Sets a property of a process. (Requires root or that the process is a child of the current process)
  * pid: The PID of the process
  * k: The key to set
  * v: The value to set
* *any* kernel.getProcessProperty(*number* pid, *string* k): Returns a property of a process. (Requires root or that the process is a child of the current process)
  * pid: The PID of the process
  * k: The key to get
  * Returns: The property
* *enumeration* kernel.arguments: Possible arguments to the kernel
  * single_user
* *table* kernel.getProcesses(): Returns a copy of the process table.
* *nil* kernel.receive(*table* handlers): Creates an event loop that calls handlers when an event is sent.
  * handlers: A table of event handlers with the format {event_1 = function(...), event_2 = function(...), ...} (return true on any to exit)
* *CCLog* kernel.log: Kernel log file (see `CCLog` for more details)
* *handle* kernel.popen(*string* path, *string* mode\[, *table* env\], ...): Starts a process from a file and returns a handle for reading or writing depending on the mode.
  * path: The path to run
  * mode: The file mode to open ("r" or "w")
  * env: Optional, the environment table of the new program (otherwise, ...)
  * ...: Any arguments to pass to the file
* *handle* kernel.popen_screen(*string* path, *string* mode\[, *table* env\], ...): Starts a process from a file and returns a handle for reading or writing depending on the mode. (readAll() returns the contents of the screen instead of the most recent text.)
  * path: The path to run
  * mode: The file mode to open ("r" or "w")
  * env: Optional, the environment table of the new program (otherwise, ...)
  * ...: Any arguments to pass to the file
* *boolean* kernel.isPiped(): Returns whether the current program is being piped.
* *boolean* kernel.isOutputPiped(): Returns whether the output is being piped.
* *boolean* kernel.isInputPiped(): Returns whether the input is being piped.

### permissions (enumeration)
* none = 0x0
* read = 0x1
* write = 0x2
* read_write = 0x3
* delete = 0x4
* read_delete = 0x5
* write_delete = 0x6
* deny_execute = 0x7
* execute = 0x8
* read_execute = 0x9
* write_execute = 0xA
* deny_delete = 0xB
* delete_execute = 0xC
* deny_write = 0xD
* deny_read = 0xE
* full = 0xF
* setuid = 0x10

### os
* *string* os.APIPath(): Returns the current path string for os.loadAPI.
* *nil* os.setAPIPath(*string* _sPath): Sets the current path string for os.loadAPI.
  * _sPath: The new path string
* *boolean* os.loadAPI(*string* _sPath): Loads an API into the global table. (Override)
  * _sPath: The path to the API, either absolute, local to a path entry, or local to the shell (if applicable)
  * Returns: Whether the API could be loaded
  * Overridden: Added path and shell resolution
* *boolean* os.run(*table* _tEnv, *string* _sPath, ...): Runs a script from a file. (Override)
  * _tEnv: The environment table of the script
  * _sPath: The path to the file
  * ...: Any arguments to pass to the file
  * Returns: Whether the script succeeded
  * Overridden: Starts a new process and waits for it to complete.
* *string, ...* os.pullEvent(\[*string* filter\]): Waits for an event to be sent, with an optional filter. (Override)
  * filter: An optional filter to restrict incoming events
  * Returns: The event name + any arguments passed
  * Overridden: Added ability to pass functions in events
* *nil* os.queueEvent(*string* event, ...): Queues an event for the current process. (Override)
  * event: The name of the event
  * ...: Any args to pass in the event
  * Overridden: Added ability to pass functions in events, restricted events to current process

### signal (enumeration)
* SIGHUP
* SIGINT
* SIGQUIT
* SIGILL
* SIGTRAP
* SIGABRT
* SIGBUS
* SIGFPE
* SIGKILL
* SIGUSR1 
* SIGSEGV 
* SIGUSR2 
* SIGPIPE 
* SIGALRM 
* SIGTERM 
* SIGSTOP 
* SIGCONT 
* SIGIO
* *string* getName(*number* sig): Returns the name of a signal

### table
* *table* table.keys(*table* t): Returns a list of keys in a table.
  * t: The table to get keys from
  * Returns: A table with the keys of `t`

### textutils
* *string* textutils.serialize(*table* t): Converts a table to a string. (Override)
  * t: The table to convert
  * Returns: A string with the serialized table
  * Overridden: Added ability to "serialize" function for debugging
* *nil* textutils.serializeFile(*string* path, *table* tab): Writes a table to a file.
  * path: The absolute path to the file
  * tab: The table to write
* *table* textutils.unserializeFile(*string* path): Reads a table from a file.
  * path: The absolute path to the file
  * Returns: The table in the file or `nil` on failure

### users
* *number* users.getuid(): Returns the current process's UID.
* *nil* users.setuid(*number* uid): Sets the current process's UID. (Requires root)
* *string* users.getFullName(*number* uid): Returns the full name for a user.
* *string* users.getShortName(*number* uid): Returns the short name for a user.
* *number* users.getUIDFromName(*string* name): Returns the UID for a short name.
* *number* users.getUIDFromFullName(*string* name): Returns the UID for a full name.
* *boolean* users.checkPassword(*number* uid, *string* password): Checks if a user-password combination is correct.
* *string* users.getHomeDir(): Returns the path to the current user's home directory.
* *nil* users.create(*string* name, *number* uid): Creates a new user. (Requires root)
  * name: The short name for the new user
  * uid: The UID of the new user
* *nil* users.setFullName(*string* name): Sets the current user's full name.
* *nil* users.setPassword(*number* uid, *string* password): Sets a user's password. (Requires root to set any user, non-root can only set own password)
  * uid: The UID of the user
  * password: The new password for the user
* *nil* users.delete(*number* uid): Deletes a user. (Requires root)
  * uid: The UID of the user
* *boolean* users.hasBlankPassword(*number* uid): Returns whether a user has no password.