_G.LibDeflate = dofile(shell.resolveProgram("LibDeflate"))
os.loadAPI(shell.resolveProgram("archive"))

local mfile = fs.open(shell.resolve("manifest.ltn"), "r")
local manifest = textutils.unserialize(mfile.readAll())
mfile.close()

local pkg = archive.new()
for k,v in pairs(manifest.files) do pkg.readFile(shell.resolve(k), k) end
pkg.readFile(shell.resolve("manifest.ltn"), "manifest.ltn")
pkg.write(shell.dir() .. "/CCKernel2.cpkg")