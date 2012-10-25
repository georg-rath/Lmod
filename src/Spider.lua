require("TermWidth")
require("border")
require("strict")
require("string_split")
require("string_trim")
require("fileOps")
require("fillWords")
require("capture")
require("pairsByKeys")
require("pager")

local M = {}

local Dbg         = require("Dbg")
local assert      = assert
local border      = border
local capture     = capture
local cmdDir      = cmdDir
local concatTbl   = table.concat
local extname     = extname
local fillWords   = fillWords
local io          = io
local ipairs      = ipairs
local lfs         = require("lfs")
local loadfile    = loadfile
local loadstring  = loadstring
local next        = next
local pairs       = pairs
local pairsByKeys = pairsByKeys 
local pathJoin    = pathJoin
local posix       = require("posix")
local print       = print
local os          = os
local systemG     = _G
local tonumber    = tonumber
local tostring    = tostring
local type        = type

function nothing()
end

local master    = {}

function masterTbl()
   return master
end

local masterTbl = masterTbl

function Spider_setenv(name, value)
   if (name:find("^TACC_.*_LIB")) then
      processLPATH(value)
   end
end   

function Spider_myFileName()
   local masterTbl   = masterTbl()
   local moduleStack = masterTbl.moduleStack 
   local iStack      = #moduleStack
   return moduleStack[iStack].fn
end

function Spider_help(...)
   local masterTbl   = masterTbl()
   local moduleStack = masterTbl.moduleStack 
   local iStack      = #moduleStack
   local path        = moduleStack[iStack].path
   local moduleT     = moduleStack[iStack].moduleT
   moduleT[path].help = concatTbl({...},"")
end

KeyT = {Description=1, Name=1, URL=1, Version=1, Category=1, Keyword=1}

function Spider_whatis(s)
   local masterTbl   = masterTbl()
   local moduleStack = masterTbl.moduleStack 
   local iStack      = #moduleStack
   local path        = moduleStack[iStack].path
   local moduleT     = moduleStack[iStack].moduleT

   local i,j, key, value = s:find('^%s*([^: ]+)%s*:%s*(.*)')
   local k  = KeyT[key]
   if (k) then
      moduleT[path][key] = value
   end
   if (moduleT[path].whatis == nil) then
      moduleT[path].whatis ={}
   end
   moduleT[path].whatis[#moduleT[path].whatis+1] = s
end

function processLPATH(value)
   local masterTbl      = masterTbl()
   local moduleStack    = masterTbl.moduleStack 
   local iStack         = #moduleStack
   local path           = moduleStack[iStack].path
   local moduleT        = moduleStack[iStack].moduleT
   
   local lpathA         = moduleT[path].lpathA or {}
   value                = path_regularize(value)
   lpathA[value]        = 1
   moduleT[path].lpathA = lpathA
end

function processPATH(value)
   if value == nil then return end

   local masterTbl     = masterTbl()
   local moduleStack   = masterTbl.moduleStack 
   local iStack        = #moduleStack
   local path          = moduleStack[iStack].path
   local moduleT       = moduleStack[iStack].moduleT
   
   local pathA         = moduleT[path].pathA or {}
   value               = path_regularize(value)
   pathA[value]        = 1
   moduleT[path].pathA = pathA
end


function Spider_append_path(kind, name, value)
   if (name == "MODULEPATH") then
      local dbg = Dbg:dbg()
      dbg.start(kind,"(MODULEPATH=\"",name,"\", value=\"",value,"\")")
      processNewModulePATH(value)
      dbg.fini()
   elseif (name == "PATH") then
      processPATH(value)
   elseif (name == "LD_LIBRARY_PATH") then
      processLPATH(value)
   end
end

function processNewModulePATH(value)
   local dbg = Dbg:dbg()
   dbg.start("processNewModulePATH(value=\"",value,"\")")

   local masterTbl   = masterTbl()
   local moduleStack = masterTbl.moduleStack 
   local iStack      = #moduleStack
   if (masterTbl.no_recursion) then
      dbg.fini()
      return
   end

   for v in value:split(":") do
      v = path_regularize(v)
      dbg.print("v: ", v,"\n")
      local path    = moduleStack[iStack].path
      local full    = moduleStack[iStack].full
      local moduleT = moduleStack[iStack].moduleT
      iStack        = iStack+1
      moduleStack[iStack] = {path = path, full = full, moduleT = moduleT[path].children, fn= v}
      dbg.print("Top of Stack: ",iStack, " Full: ", full, " file: ", path, "\n")
      M.findModulesInDir(v,v,"",moduleT[path].children)
      moduleStack[iStack] = nil
   end

   dbg.fini()
end

function Spider_add_property(name,value)
   local dbg = Dbg:dbg()
   dbg.start("Spider_add_property(name=\"",name,"\", value=\"",value,"\")")

   local masterTbl     = masterTbl()
   local moduleStack   = masterTbl.moduleStack 
   local iStack        = #moduleStack
   local path          = moduleStack[iStack].path
   local moduleT       = moduleStack[iStack].moduleT
   local t             = moduleT[path].propT or {}
   t[name]             = t[name] or {}
   t[name][value]      = 1
   moduleT[path].propT = t
   dbg.fini()
end

function Spider_remove_property(name,value)
   local dbg = Dbg:dbg()
   dbg.start("Spider_remove_property(name=\"",name,"\", value=\"",value,"\")")
   local masterTbl     = masterTbl()
   local moduleStack   = masterTbl.moduleStack 
   local iStack        = #moduleStack
   local path          = moduleStack[iStack].path
   local moduleT       = moduleStack[iStack].moduleT
   local t             = moduleT[path].propT or {}
   t[name]             = t[name] or {}
   t[name][value]      = nil
   moduleT[path].propT = t
   dbg.fini()
end


------------------------------------------------------------
--module("Spider")
------------------------------------------------------------


local function lastFileInDir(fn)
   local dbg      = Dbg:dbg()
   dbg.start("lastFileInDir(",fn,")")
   local lastKey   = ''
   local lastValue = ''
   local result    = nil
   local fullName  = nil
   local count     = 0
   
   local attr = lfs.attributes(fn)
   if (attr and attr.mode == 'directory' and posix.access(fn,"x")) then
      for file in lfs.dir(fn) do
         local f = pathJoin(fn, file)
         dbg.print("fn: ",fn," file: ",file," f: ",f,"\n")
         attr = lfs.attributes(f)
         local readable = posix.access(f,"r")
         if (readable and file:sub(1,1) ~= "." and attr.mode == 'file' and file:sub(-1,-1) ~= '~') then
            count = count + 1
            local key = f:gsub("%.lua$","")
            if (key > lastKey) then
               lastKey   = key
               lastValue = f
            end
         end
      end
      if (lastKey ~= "") then
         result     = lastValue
      end
   end
   dbg.print("result: ",tostring(result),"\n")
   dbg.fini()
   return result, count
end

local function findDefault(mpath, path, prefix)
   local dbg      = Dbg:dbg()
   local mt       = MT:mt()
   local localDir = true
   dbg.start("Master.findDefault(",mpath,", ", path,", ",prefix,")")

   if (prefix == "") then
      dbg.fini()
      return nil
   end

   --dbg.print("abspath(\"", tostring(path .. "/default"), ", \"",tostring(localDir),"\")\n")
   local default = abspath(path .. "/default", localDir)
   --dbg.print("(2) default: ", tostring(default), "\n")
   if (default == nil) then
      local vFn = abspath(pathJoin(path,".version"), localDir)
      if (isFile(vFn)) then
         local vf = M.versionFile(vFn)
         if (vf) then
            local f = pathJoin(path,vf)
            default = abspath(f,localDir)
            --dbg.print("(1) f: ",f," default: ", tostring(default), "\n")
            if (default == nil) then
               local fn = vf .. ".lua"
               local f  = pathJoin(path,fn)
               default  = abspath(f,localDir)
               dbg.print("(2) f: ",f," default: ", tostring(default), "\n")
            end
            --dbg.print("(3) default: ", tostring(default), "\n")
         end
      end
   end
   if (default == nil and prefix ~= "") then
      local result, count = lastFileInDir(path)
      default = result
   end
   if (default) then
      default = abspath(default, localDir)
   end
   dbg.print("(4) default: \"",tostring(default),"\"\n")

   dbg.fini()
   return default
end

local function loadModuleFile(fn)
   local dbg    = Dbg:dbg()
   dbg.start("loadModuleFile(" .. fn .. ")")
   dbg.flush()

   systemG._MyFileName = fn
   local myType = extname(fn)
   local func
   local msg
   if (myType == ".lua") then
      func, msg = loadfile(fn)
   else
      local a     = {}
      a[#a + 1]	  = pathJoin(cmdDir(),"tcl2lua.tcl")
      a[#a + 1]	  = "-h"
      a[#a + 1]	  = fn
      local cmd   = concatTbl(a," ")
      local s     = capture(cmd)
      func, msg = loadstring(s)
   end
   if (func) then
      func()
   else
      dbg.warning("Syntax error: ",msg,"\n")
   end
   dbg.fini()
end


local function fullName(name)
   local n    = nil
   if (name == nil) then return n end
   local i,j  = name:find('.*/')
   i,j        = name:find('.*%.',j)
   if (i == nil) then
      n = name
   else
      local ext = name:sub(j,-1)
      if (ext == ".lua") then
         n = name:sub(1,j-1)
      else
         n = name
      end
   end
   return n
end


local function extractName(full)
   local i, j
   local n = nil
   if (full == nil) then return n end

   -- extract to first directory name
   i, j, n = full:find('([^/]+)/') 
   if (n) then
      return n
   end

   -- Remove any extension
   i, j, n   = full:find('(.*)%.')
   if (n == nil) then
      n = full
   end
   return n
end

function M.findModulesInDir(mpath, path, prefix, moduleT)
   local dbg  = Dbg:dbg()
   dbg.start("findModulesInDir(mpath=\"",mpath," path=\"",path,"\", prefix=\"",prefix,"\")")

   local attr = lfs.attributes(mpath)
   if (not attr) then
      dbg.fini()
      return
   end

   assert(type(attr) == "table")
   if ( attr.mode ~= "directory" or not posix.access(mpath,"rx")) then
      dbg.fini()
      return
   end
   
   local masterTbl       = masterTbl()
   local moduleStack     = masterTbl.moduleStack
   local iStack          = #moduleStack
   
   local defaultModuleName = findDefault(mpath, path, prefix)

   for file in lfs.dir(path) do
      if (file:sub(1,1) ~= "." and not file ~= "CVS" and file:sub(-1,-1) ~= "~") then
         local f = pathJoin(path,file)
         local readable = posix.access(f,"r")
         attr = lfs.attributes(f) or {}
         dbg.print("file: ",file," f: ",f," attr.mode: ", attr.mode,"\n")
	 if (readable and (attr.mode == 'file' or attr.mode == 'link') and (file ~= "default")) then
            if (moduleT[f] == nil) then
               local full    = fullName(pathJoin(prefix,file))
               local fullL   = full:lower()
               local name    = extractName(full)
               local nameL   = name:lower()
               local epoch   = attr.modification
               local default = (f == defaultModuleName)
               moduleT[f]    = { path = f, name = name, name_lower = nameL,
                                 full = full, full_lower = fullL, epoch = epoch,
                                 default = default,
                                 children = {}
                                 
               }
               moduleStack[iStack] = {path=f, full = full, moduleT = moduleT, fn = f}
               dbg.print("Top of Stack: ",iStack, " Full: ", full, " file: ", f, "\n")
               loadModuleFile(f)
               dbg.print("Saving: Full: ", full, " Name: ", name, " file: ",f,"\n")
            end
         elseif (attr.mode == 'directory') then
            M.findModulesInDir(mpath, f, prefix .. file..'/',moduleT)
	 end
      end
   end
   dbg.fini()
end

function M.findAllModules(moduleDirA, moduleT)
   local dbg    = Dbg:dbg()
   dbg.start("findAllModules(",concatTbl(moduleDirA,", "),")")
   
   local myFileN_old     = myFileName
   myFileName            = Spider_myFileName
   local masterTbl       = masterTbl()
   local moduleDirT      = {}
   masterTbl.moduleDirT  = moduleDirT
   masterTbl.moduleT     = moduleT
   masterTbl.moduleStack = {{}}
   local exit            = os.exit
   os.exit               = nothing

   for _,v in ipairs(moduleDirA) do
      v             = path_regularize(v)
      if (moduleDirT[v] == nil) then
         moduleDirT[v] = 1
         M.findModulesInDir(v, v, "", moduleT)
      end
   end
   os.exit     = exit

   myFileName = myFileN_old
   dbg.fini()
end

function M.buildSpiderDB(a, moduleT, dbT)
   local dbg = Dbg:dbg()
   dbg.start("buildSpiderDB({",concatTbl(a,","),"},moduleT, dbT)")
   for path, value in pairs(moduleT) do
      local nameL = value.name_lower or value.name:lower()
      dbT[nameL]  = dbT[nameL] or {}
      local t     = dbT[nameL]

      for k, v in pairs(value) do
         if (t[path] == nil) then
            t[path] = {}
         end
         if (k ~= "children") then
            t[path][k] = v
         end
      end
      local parent = t[path].parent or {}
      local entry  = concatTbl(a,":")
      local found  = false
      for i = 1,#parent do
         if ( entry == parent[i]) then
            found = true
            break;
         end
      end
      if (not found) then
         parent[#parent+1] = entry
      end
      t[path].parent = parent
      if (next(value.children)) then
         a[#a+1] = t[path].full
         M.buildSpiderDB(a, value.children, dbT)
         a[#a]   = nil
      end
   end
   dbg.fini()
end

function M.searchSpiderDB(strA, a, moduleT, dbT)
   local dbg = Dbg:dbg()
   dbg.start("searchSpiderDB()")

   for path, value in pairs(moduleT) do
      local nameL   = value.name_lower or ""
      local full    = value.full
      local whatisT = value.whatis or {}
      local whatisS = concatTbl(whatisT,"\n")

      if (dbT[nameL] == nil) then
         dbT[nameL] = {}
      end
      local t = dbT[nameL]

      local found = false
      for i = 1,#strA do
         local str = strA[i]:lower()
         if (nameL:find(str,1,true) or whatisS:find(str,1,true) or 
             nameL:find(str)        or whatisS:find(str)) then
            found = true
            break
         end
      end
      if (found) then
         for k, v in pairs(value) do
            if (t[path] == nil) then
               t[path] = {}
            end
            if (k ~= "children") then
               t[path][k] = v
            end
         end
         local parent = t[path].parent or {}
         parent[#parent+1] = concatTbl(a,":")
         t[path].parent = parent
      end
      if (next(value.children)) then
         a[#a+1] = full
         M.searchSpiderDB(strA, a, value.children, dbT)
         a[#a]   = nil
      end
   end
   dbg.fini()
end

function M.Level0(dbT)

   local a      = {}
   local ia     = 0
   local banner = border(0)


   ia = ia+1; a[ia] = "\n"
   ia = ia+1; a[ia] = banner
   ia = ia+1; a[ia] = "The following is a list of the modules currently available:\n"
   ia = ia+1; a[ia] = banner

   M.Level0Helper(dbT,a)

   return concatTbl(a,"")
end

function M.Level0Helper(dbT,a)
   local t          = {}
   local term_width = TermWidth() - 4

   for k,v in pairs(dbT) do
      for kk,vv in pairsByKeys(v) do
         if (t[k] == nil) then
            t[k] = { Description = vv.Description, Versions = { }, name = vv.name}
            t[k].Versions[vv.full] = 1
         else
            t[k].Versions[vv.full] = 1
         end
      end
   end

   local ia = #a

   for k,v in pairsByKeys(t) do
      local len = 0
      ia = ia + 1; a[ia] = "  " .. v.name .. ":"
      len = len + a[ia]:len()
      for kk,_ in pairsByKeys(v.Versions) do
         ia = ia + 1; a[ia] = " " .. kk; len = len + a[ia]:len() + 1
         if (len > term_width) then
            a[ia] = " ..."
            ia = ia + 1; a[ia] = ","
            break;
         end
         ia = ia + 1; a[ia] = ","
      end
      a[ia] = "\n"  -- overwrite the last comma
      if (v.Description) then
         ia = ia + 1; a[ia] = fillWords("    ",v.Description, term_width)
         ia = ia + 1; a[ia] = "\n"
      end
      ia = ia + 1; a[ia] = "\n"
   end
   local banner = border(0)
   ia = ia+1; a[ia] = banner
   ia = ia+1; a[ia] = "To learn more about a package enter:\n\n"
   ia = ia+1; a[ia] = "   $ module spider Foo\n\n"
   ia = ia+1; a[ia] = "where \"Foo\" is the name of a module\n\n"
   ia = ia+1; a[ia] = "To find detailed information about a particular package you\n"
   ia = ia+1; a[ia] = "must enter the version if there is more than one version:\n\n"
   ia = ia+1; a[ia] = "   $ module spider Foo/11.1\n"
   ia = ia+1; a[ia] = banner

end


local function countEntries(t, mname)
   local count   = 0
   local nameCnt = 0
   for k,v in pairs(t) do
      count = count + 1
      if (v.name == mname) then
         nameCnt = nameCnt + 1
      end
   end
   return count, nameCnt
end

function M.spiderSearch(dbT, mname, help)
   local dbg = Dbg:dbg()
   dbg.start("Spider:spiderSearch(dbT,\"",mname,"\")")
   local name   = extractName(mname)
   local nameL  = name:lower()
   local mnameL = mname:lower()
   local found  = false
   local a      = {}
   for k,v in pairs(dbT) do
      if (k:find(nameL,1,true) or k:find(nameL)) then
         local s
         dbg.print("nameL: ",nameL," mnameL: ", mnameL, " k: ",k,"\n")
         if (nameL ~= mnameL ) then
            if (nameL == k) then
                s = M.Level2(v, mname)
                found = true
            end
         else
            s = M.Level1(dbT, k, help)
            found = true
         end
         if (s) then
            a[#a+1] = s
            s       = nil
         end
      end
   end
   if (not found) then
      io.stderr:write("Unable to find: \"",mname,"\"\n")
   end
   dbg.fini()
   return concatTbl(a,"")
end

function M.Level1(dbT, mname, help)
   local dbg = Dbg:dbg()
   dbg.start("Level1(dbT,\"",mname,"\",help)")
   local name       = extractName(mname)
   local nameL      = name:lower()
   local t          = dbT[nameL]
   local term_width = TermWidth() - 4
   dbg.print("mname: ", mname, ", name: ",name,"\n")

   if (t == nil) then
      return ""
   end

   local cnt, nameCnt = countEntries(t, mname)
   dbg.print("Number of entries: ",cnt ," name count: ",nameCnt, "\n")
   if (cnt == 1 or nameCnt == 1) then
      local k = next(t)
      return M.Level2(t, mname, t[k].full)
   end
      
   local banner = border(2)
   local VersionT = {}
   local exampleV = nil
   local key = nil
   local Description = nil
   for k, v in pairsByKeys(t) do
      if (VersionT[k] == nil) then
         key = v.name
         Description = v.Description 
         VersionT[v.full] = 1
         exampleV = v.full
      else
         VersionT[v.full] = 1
      end
   end

   local a  = {}
   local ia = 0

   ia = ia + 1; a[ia] = "\n"
   ia = ia + 1; a[ia] = banner
   ia = ia + 1; a[ia] = "  " .. key .. ":\n"
   ia = ia + 1; a[ia] = banner
   if (Description) then
      ia = ia + 1; a[ia] = "    Description:\n"
      ia = ia + 1; a[ia] = fillWords("      ",Description,term_width)
      ia = ia + 1; a[ia] = "\n\n"
      
   end
   ia = ia + 1; a[ia] = "     Versions:\n"
   for k, v in pairsByKeys(VersionT) do
      ia = ia + 1; a[ia] = "        " .. k .. "\n"
   end

   if (help) then
      ia = ia + 1; a[ia] = "\n"
      ia = ia + 1; a[ia] = banner
      ia = ia + 1; a[ia] = "  To find detailed information about "
      ia = ia + 1; a[ia] = key
      ia = ia + 1; a[ia] = " please enter the full name.\n  For example:\n\n"
      ia = ia + 1; a[ia] = "     $ module spider "
      ia = ia + 1; a[ia] = exampleV
      ia = ia + 1; a[ia] = "\n"
      ia = ia + 1; a[ia] = banner
   end

   dbg.fini()
   return concatTbl(a,"")
   
end

function M.Level2(t, mname, full)
   local dbg = Dbg:dbg()
   dbg.start("Level2(t,\"",mname,"\", \"",tostring(full),"\")")
   local a  = {}
   local ia = 0
   local b  = {}
   local c  = {}
   local titleIdx = 0
   
   local propDisplayT = readRC()
   
   local term_width = TermWidth() - 4
   local tt = nil
   local banner = border(2)
   local availT = {
      "\n    This module can be loaded directly: module load " .. mname .. "\n",
      "\n    This module can only be loaded through the following modules:\n",
      "\n    This module can be loaded directly: module load " .. mname .. "\n" ..
      "\n    Additional variants of this module can also be loaded after the loading the following modules:\n",
   }
   local haveCore = 0
   local haveHier = 0
   local mnameL   = mname:lower()
      
   full = full or ""
   local fullL = full:lower()
   for k,v in pairs(t) do
      dbg.print("vv.full: ",v.full," mname: ",mname," k: ",k," full:", tostring(full),"\n")
      if (v.full_lower == mnameL or v.full_lower == fullL) then
         if (tt == nil) then
            tt = v
            ia = ia + 1; a[ia] = "\n"
            ia = ia + 1; a[ia] = banner
            ia = ia + 1; a[ia] = "  " .. tt.name .. ": "
            ia = ia + 1; a[ia] = tt.full 
            ia = ia + 1; a[ia] = "\n"
            ia = ia + 1; a[ia] = banner
            if (tt.Description) then
               ia = ia + 1; a[ia] = "    Description:\n"
               ia = ia + 1; a[ia] = fillWords("      ",tt.Description, term_width)
               ia = ia + 1; a[ia] = "\n"
            end
            if (tt.propT ) then
               ia = ia + 1; a[ia] = "    Properties:\n"
               for kk, vv in pairs(propDisplayT) do
                  if (tt.propT[kk]) then
                     for kkk in pairs(tt.propT[kk]) do
                        if (vv.displayT[kkk]) then
                           ia = ia + 1; a[ia] = fillWords("      ",vv.displayT[kkk].doc, term_width)
                        end
                     end
                  end
               end
               ia = ia + 1; a[ia] = "\n"
            end
            ia = ia + 1; a[ia] = "Avail Title goes here.  This should never be seen\n"
            titleIdx = ia
         end
         if (#v.parent == 1 and v.parent[1] == "default") then
            haveCore = 1
         else
            b[#b+1] = "      "
            haveHier = 2
         end

         for i = 1, #v.parent do
            local entry = v.parent[i]
            for s in entry:split(":") do
               if (s ~= "default") then
                  b[#b+1] = s
                  b[#b+1] = ', '
               end
            end
            b[#b] = "\n      "
         end
         if (#b > 0) then
            b[#b] = "\n" -- Remove final comma add newline instead
            c[#c+1] = concatTbl(b,"")
            b = {}
         end
      end
   end
   a[titleIdx] = availT[haveCore+haveHier]
   if (#c > 0) then

      -- remove any duplicates
      local s = concatTbl(c,"")
      local d = {}
      for k in s:split("\n") do
         d[k] = 1
      end
      c = {}
      for k in pairs(d) do
         c[#c+1] = k
      end
      table.sort(c)
      c[#c+1] = " "
      ia = ia + 1; a[ia] = concatTbl(c,"\n")
   end

   if (tt and tt.help ~= nil) then
      ia = ia + 1; a[ia] = "\n    Help:\n"
      for s in tt.help:split("\n") do
         ia = ia + 1; a[ia] = "      "
         ia = ia + 1; a[ia] = s
         ia = ia + 1; a[ia] = "\n"
      end
   end

   if (tt == nil) then
      LmodSystemError("Unable to find: \"",mname,"\"")
   end

   dbg.fini()
   return concatTbl(a,"")
end

function M.listModules(t,tbl)
   for k,v in pairs(t) do
      tbl[#tbl+1] = v.path
      if (next(v.children)) then
         M.listModules(v.children,tbl)
      end
   end
end

function M.dictModules(t,tbl)
   for k,v in pairs(t) do
      k      = k:gsub(".lua$","")
      tbl[k] = 0
      if (next(v.children)) then
         M.dictModules(v.children,tbl)
      end
   end
end

return M
