fs.makeDir("/usr")
fs.makeDir("/etc")
if fs.exists("/usr/bin") then fs.delete("/usr/bin") end
if fs.exists("/usr/libexec") then fs.delete("/usr/libexec") end
if fs.exists("/etc/init") then fs.delete("/etc/init") end
fs.copy(shell.resolve("bin"), "/usr/bin")
fs.copy(shell.resolve("init"), "/etc/init")