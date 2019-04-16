if kernel == nil then print("This requires CCKernel2.") end
kernel.log:info("Welcome to CCKernel2!")

function status(stat, message)
    if stat == nil then 
        write("        ")
        kernel.log:info(message)
    elseif stat then 
        term.blit("[ OK ]  ", "05555000", "ffffffff")
        kernel.log:info(message)
    else 
        term.blit("[FAIL]  ", "0eeee000", "ffffffff") 
        kernel.log:error(message)
    end
    print(message)
end

fs.makeDir("/etc/sysd")

-- TODO