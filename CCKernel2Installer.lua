print("Loading installer...")
_G.LibDeflate = dofile(shell.resolveProgram("LibDeflate"))
if not LibDeflate then return end
if not os.loadAPI(shell.resolveProgram("archive")) then return end
_G.CCLog = dofile(shell.resolveProgram("CCLog"))
if not CCLog then return end
if not os.loadAPI(shell.resolveProgram("CCKit")) then return end
if not os.loadAPI(shell.resolveProgram("CCOSCrypto")) then return end
local pkg = archive.read(shell.resolve("CCKernel2.cpkg"))
if not pkg then error("Could not find package") end

local function WelcomeViewController()
    local retval = CCKit.CCViewController()
    retval.back = CCKit.CCButton(5, 14, 8, 1)
    retval.next = CCKit.CCButton(19, 14, 8, 1)
    function retval:exit()
        self.application:deregisterObject(self.back.name)
        self.application:deregisterObject(self.next.name)
        self.window:close()
    end
    function retval:continue()
        local vc = ReadmeViewController()
        self.application:deregisterObject(self.back.name)
        self.application:deregisterObject(self.next.name)
        self.window:setViewController(vc, self.application)
    end
    function retval:viewDidLoad()
        local title = CCKit.CCLabel(1, 1, "* Welcome")
        self.view:addSubview(title)
        local text = CCKit.CCTextView(1, 3, 30, 10)
        text:setText("Welcome to the setup program for CCKernel2. You will be guided through the steps necessary to install CCKernel2.")
        self.view:addSubview(text)
        self.back:setText("Cancel")
        self.back:setAction(self.exit, self)
        self.view:addSubview(self.back)
        self.next:setText("Next")
        self.next:setAction(self.continue, self)
        self.view:addSubview(self.next)
    end
    return retval
end

function ReadmeViewController()
    local retval = CCKit.CCViewController()
    retval.back = CCKit.CCButton(5, 14, 8, 1)
    retval.next = CCKit.CCButton(19, 14, 8, 1)
    function retval:goback()
        self.application:deregisterObject(self.back.name)
        self.application:deregisterObject(self.next.name)
        self.window:setViewController(WelcomeViewController(), self.application)
    end
    function retval:continue()
        self.application:deregisterObject(self.back.name)
        self.application:deregisterObject(self.next.name)
        self.window:setViewController(ConfigureViewController(), self.application)
    end
    function retval:viewDidLoad()
        local title = CCKit.CCLabel(1, 1, "* Readme")
        self.view:addSubview(title)
        local text = CCKit.CCTextView(0, 0, 30, 55)
        text:setText([[CCKernel2 is the most advanced extension to CraftOS ever made. It adds a significant number of new features, including:
* Cooperative multiprocessing
* Native IPC calls
* Process signaling
* A built-in Lua debugger
* A multi-user system
* File permissions
* Device files (/dev)
* Eight virtual terminals
* A Built-in logger
* A Unix-style file hierarchy
* `os.loadAPI` resolution paths
* Process I/O pipes
* A systemd-like init program
* Many new shell programs
CCKernel2 is designed to complement the existing CraftOS shell while rewriting much of its functionality. The fs API has been completely rewritten from the ground up to support user permissions.
On the next page, you will be asked to create a new user. You will log in with the short name and password you set, while the full name is used in supported applications. You can also let CCKernel2 run at startup, or you can choose to run CCKernel2 manually.
CCKernel2's API reference can be viewed through the built-in help articles that will be installed.

CCKernel2 was made by JackMacWindows (GitHub: MCJack123), available as a free and open-source project on GitHub. Feel free to submit any issues with the program.]])
        local scroll = CCKit.CCScrollView(1, 3, 31, 10, 55)
        self.view:addSubview(scroll)
        scroll:addSubview(text)
        self.back:setText("Back")
        self.back:setAction(self.goback, self)
        self.view:addSubview(self.back)
        self.next:setText("Next")
        self.next:setAction(self.continue, self)
        self.view:addSubview(self.next)
    end
    return retval
end

local fullName, shortName, password, startup

function ConfigureViewController()
    local retval = CCKit.CCViewController()
    retval.back = CCKit.CCButton(5, 14, 8, 1)
    retval.next = CCKit.CCButton(19, 14, 8, 1)
    retval.fullNameBox = CCKit.CCTextField(12, 3, 18)
    retval.shortNameBox = CCKit.CCTextField(13, 5, 17)
    retval.passwordBox = CCKit.CCTextField(11, 7, 19)
    retval.startup = CCKit.CCCheckbox(1, 9, "Run CCKernel2 at startup")
    function retval:goback()
        local vc = ReadmeViewController()
        self.application:deregisterObject(self.back.name)
        self.application:deregisterObject(self.next.name)
        self.application:deregisterObject(self.fullNameBox.name)
        self.application:deregisterObject(self.shortNameBox.name)
        self.application:deregisterObject(self.passwordBox.name)
        self.application:deregisterObject(self.startup.name)
        self.window:setViewController(vc, self.application)
    end
    function retval:continue()
        if self.fullNameBox.text == "" or self.shortNameBox.text == "" or self.passwordBox.text == "" then
            local alert = CCKit.CCAlertWindow(2, 2, 10, 5, "Alert", "Please fill in all fields.", self.application)
            self.window:present(alert)
            return
        end
        fullName = self.fullNameBox.text
        shortName = self.shortNameBox.text
        password = self.passwordBox.text
        startup = self.startup.isOn
        self.application:deregisterObject(self.back.name)
        self.application:deregisterObject(self.next.name)
        self.application:deregisterObject(self.fullNameBox.name)
        self.application:deregisterObject(self.shortNameBox.name)
        self.application:deregisterObject(self.passwordBox.name)
        self.application:deregisterObject(self.startup.name)
        self.window:setViewController(InstallViewController(), self.application)
    end
    function retval:viewDidLoad()
        local title = CCKit.CCLabel(1, 1, "* Configuration")
        self.view:addSubview(title)
        local fullNameLabel = CCKit.CCLabel(1, 3, "Full Name: ")
        self.view:addSubview(fullNameLabel)
        self.fullNameBox.placeholderText = "Full name"
        self.view:addSubview(self.fullNameBox)
        local shortNameLabel = CCKit.CCLabel(1, 5, "Short Name: ")
        self.view:addSubview(shortNameLabel)
        self.shortNameBox.placeholderText = "Short name"
        self.view:addSubview(self.shortNameBox)
        local passwordLabel = CCKit.CCLabel(1, 7, "Password: ")
        self.view:addSubview(passwordLabel)
        self.passwordBox.placeholderText = "Password"
        self.passwordBox.textReplacement = "*"
        self.view:addSubview(self.passwordBox)
        self.startup.isOn = true
        self.view:addSubview(self.startup)
        self.back:setText("Back")
        self.back:setAction(self.goback, self)
        self.view:addSubview(self.back)
        self.next:setText("Next")
        self.next:setAction(self.continue, self)
        self.view:addSubview(self.next)
    end
    return retval
end

function InstallViewController()
    local retval = CCKit.CCViewController()
    retval.back = CCKit.CCButton(5, 14, 8, 1)
    retval.next = CCKit.CCButton(19, 14, 8, 1)
    function retval:goback()
        local vc = ReadmeViewController()
        self.application:deregisterObject(self.back.name)
        self.application:deregisterObject(self.next.name)
        self.window:setViewController(vc, self.application)
    end
    function retval:continue()
        local newwin = CCKit.CCWindow(14, 5, 22, 5)
        newwin:setTitle("Installing")
        local newvc = ProgressViewController()
        newwin:setViewController(newvc, self.application)
        self.window:close()
        self.window:present(newwin)
    end
    function retval:viewDidLoad()
        local title = CCKit.CCLabel(1, 1, "* Ready to Install")
        self.view:addSubview(title)
        local text = CCKit.CCTextView(1, 3, 30, 10)
        text:setText("The files will be installed to /. CCKernel2 will take up " .. pkg.size .. " bytes of space. Click Install to start the installation.")
        self.view:addSubview(text)
        self.back:setText("Back")
        self.back:setAction(self.goback, self)
        self.view:addSubview(self.back)
        self.next:setText("Install")
        self.next:setAction(self.continue, self)
        self.view:addSubview(self.next)
    end
    return retval
end

function ProgressViewController()
    local retval = CCKit.multipleInheritance(CCKit.CCViewController(), CCKit.CCEventHandler("ProgressViewController"))
    retval.progressBar = CCKit.CCProgressBar(1, 2, 20)
    retval.name = "PVC"
    retval.status = CCKit.CCTextView(1, 1, 20, 1)
    retval.started = false
    function retval:exit()
        newwin = CCKit.CCWindow(11, 5, 28, 9)
        newwin:setTitle("Complete")
        local newvc = CompleteViewController()
        newwin:setViewController(newvc, self.application)
        self.window:present(newwin)
        self.window:close()
        self.application:deregisterObject(self.name)
        return true
        --os.queueEvent("redraw_window", newwin.name)
    end
    function retval:install()
        if not retval.started then
            retval.started = true
            os.queueEvent("installing")
            return
        end
        local manifest_file = pkg.open("manifest.ltn", "r")
        local manifest = textutils.unserialize(manifest_file.readAll())
        manifest_file.close()
        local filecount = 0
        for k,v in pairs(manifest.files) do filecount = filecount + 1 end
        self.status:setText("Preparing...")
        for k,v in pairs(manifest.directories) do fs.makeDir(v) end
        self.progressBar:setIndeterminate(false)
        self.progressBar:setProgress(0.0)
        local completed = 0
        for src,dest in pairs(manifest.files) do
            self.status:setText("Installing (" .. completed + 1 .. "/" .. filecount .. ")")
            pkg.writeFile(src, dest)
            completed = completed + 1
            self.progressBar:setProgress(completed / filecount)
            self.view:draw()
            os.queueEvent("nosleep")
            os.pullEvent()
        end
        self.status:setText("Setting up...")
        self.progressBar:setIndeterminate(true)
        local file = fs.open("/etc/passwd", "w")
        file.write(textutils.serialize({
            [-1] = {name = "superroot", fullName = "Kernel Process", password = nil},
            [0] = {name = "root", fullName = "Superuser", password = nil},
            [1] = {name = shortName, fullName = fullName, password = CCOSCrypto.sha256(password)}
        }))
        file.close()
        if startup then
            local file = fs.open("/startup.lua", fs.exists("/startup.lua") and "a" or "w")
            file.writeLine("os.queueEvent(\"start\")")
            file.writeLine("shell.run(\"/kernel.lua\")")
            file.writeLine("os.shutdown()")
            file.close()
        end
        os.queueEvent("finished")
    end
    function retval:viewDidLoad()
        self.maximizable = false
        self.status.text = "Loading manifest..."
        self.progressBar.isIndeterminate = true
        self.view:addSubview(self.status)
        self.view:addSubview(self.progressBar)
        self.view:draw()
        self.window:redraw()
        self:addEvent("installing", self.install)
        self:addEvent("finished", self.exit)
        self.window:registerObject(self)
        os.queueEvent("installing")
    end
    return retval
end

function CompleteViewController()
    local retval = CCKit.CCViewController()
    function retval:exit()
        self.window:close()
        os.reboot()
    end
    function retval:viewDidLoad()
        local text = CCKit.CCTextView(1, 1, self.view.frame.width - 2, 4)
        text:setText("Installation is complete. You must restart your computer for changes to take effect.")
        self.view:addSubview(text)
        local button = CCKit.CCButton(9, 6, 8, 1)
        button:setText("Reboot")
        button:setAction(self.exit, self)
        self.view:addSubview(button)
    end
    return retval
end

CCKit.CCMain(10, 2, 32, 17, "CCKernel2 Installer", WelcomeViewController, colors.blue, "CCKernel2 Installer", true)