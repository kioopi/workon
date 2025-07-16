package = "workon"
version = "dev-1"

source = {
   url = "*** please add URL for source tarball, zip or repository here ***"
}

description = {
   summary = "WorkOn workspace bootstrapper Lua components",
   detailed = [[
      Lua components for WorkOn - a one-shot project workspace bootstrapper 
      for AwesomeWM. This package provides the core spawning functionality 
      and session management utilities.
   ]],
   homepage = "*** please add project homepage URL here ***",
   license = "MIT"
}

dependencies = {
   "lua >= 5.1, < 5.5",
   "dkjson >= 2.5"
}

build = {
   type = "builtin",
   modules = {
      ["workon.spawn"] = "src/spawn.lua",
      ["workon.session"] = "src/session.lua",
      ["workon.json"] = "src/json.lua"
   }
}