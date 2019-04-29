for _,v in pairs({...}) do
    local file = fs.open(shell.resolve(v), "r")
    if file then
        write(file.readAll())
        file.close()
    end
end