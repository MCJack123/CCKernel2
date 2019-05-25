print("Loading installer...")
os.loadAPI(shell.resolveProgram("archive"))
os.loadAPI(shell.resolveProgram("CCKit"))
local pkg = archive.load(shell.resolve("CCKernel2.ccpkg"))

local function CompleteViewController()
    local retval = CCKit.CCViewController()
    function retval:exit()
        os.queueEvent("closed_window", self.parentWindow.name)
        os.reboot()
    end
    function retval:viewDidLoad()
        local text = CCKit.CCTextView(1, 1, self.view.frame.width - 2, 3, "Installation is complete. You must restart your computer for changes to take effect.")
        self.view:addSubview(text)
        local button = CCKit.CCButton(9, 6, 8, 1)
        button:setText("Reboot")
        button:setAction(self.exit, self)
        self.view:addSubview(button)
    end
    return retval
end