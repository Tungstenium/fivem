-- componentization handlers
local components = { }

dependency = function(name)
	-- find a matching component
	--[[local cname

	for _, c in ipairs(components) do
		if c == name then
			cname = c
			break
		else
			local basename = c:gsub('(.+)-ny', '%1')

			if basename == name then
				cname = c
				break
			end
		end
	end

	if not cname then
		error("Component " .. name .. " seems unknown.")
	end

	includedirs { '../' .. name .. '/include/' }

	links { name }]]

	return
end

package.path = '?.lua'

function string:ends(match)
	return (match == '' or self:sub(-match:len()) == match)
end

local json = require('json')

-- declaration function for components (for components/config.lua)
component = function(name)
	local decoded

	if type(name) == 'string' then
		local filename = name .. '/component.json'

		io.input(filename)
		local jsonStr = io.read('*all')
		io.close()

		decoded = json.decode(jsonStr)

		decoded.rawName = name
	else
		decoded = name

		decoded.dummy = true
	end

	-- check if the project name ends in a known game name, and if we should ignore it
	for _, name in ipairs(gamenames) do
		-- if it ends in the current game name...
		if decoded.name:ends(':' .. name) then
			-- ... and it's not the current game we're targeting...
			if name ~= _OPTIONS['game'] then
				-- ... ignore it
				return
			end
		end
	end

	-- add to the list
	table.insert(components, decoded)
end

vendor_component = function(name)
	local vendorTable = dofile(name .. '.lua')

	if vendorTable then
		component {
			name = 'vendor:' .. name,
			vendor = vendorTable,
			rawName = name
		}
	end
end

local function id_matches(full, partial)
	local tokenString = ''
	local partialTemp = partial .. ':'

	for token in string.gmatch(full:gsub('\\[.+\\]', ''), '[^:]+') do
		tokenString = tokenString .. token .. ':'

		if partialTemp == tokenString then
			return true
		end
	end

	return false
end

local function find_match(id)
	for _, mcomp in ipairs(components) do
		if mcomp.name == id then
			return mcomp
		end

		if id_matches(mcomp.name, id) then
			return mcomp
		end
	end

	return nil
end

local function process_dependencies(list, basename, hasDeps)
	local isFulfilled = true

	if not basename then
		basename = project().name
	end

	if list then
		for _, dep in ipairs(list) do
			-- find a match for the dependency
			local match = find_match(dep)

			if match and not hasDeps[match.rawName] then
				print(basename .. ' dependency on ' .. dep .. ' fulfilled by ' .. match.rawName)

				hasDeps[match.rawName] = match
				match.tagged = true

				isFulfilled = isFulfilled and process_dependencies(match.dependencies, match.name, hasDeps)
			elseif not match then
				if not dep:match('%[') then
					print('Dependency unresolved for ' .. dep .. ' in ' .. basename)

					return false
				end
			end
		end
	end

	return isFulfilled
end

add_dependencies = function(list)
	if type(list) == 'string' then
		list = { list }
	end

	local hasDeps = {}

	if not process_dependencies(list, nil, hasDeps) then
		error('component dependency from ' .. project().name .. ' unresolved!')
	end

	-- loop over the dependency handlers
	for dep, data in pairs(hasDeps) do
		if not data.vendor or not data.vendor.dummy then
			links { dep }
		end

		configuration {}
		filter {}

		if data.vendor and data.vendor.include then
			data.vendor.include()
		end

		configuration {}
		filter {}

		if data.vendor and data.vendor.depend then
			data.vendor.depend()
		end
	end
end

local do_component = function(name, comp)
	-- do automatic dependencies
	if not comp.dependencies then
		comp.dependencies = {}
	end

	local hasDeps = {}

	if not process_dependencies(comp.dependencies, comp.name, hasDeps) then
		return
	end

	-- process the project

	project(name)

	language "C++"
	kind "SharedLib"

	includedirs { "client/citicore/", 'components/' .. name .. "/include/" }
	files {
		'components/' .. name .. "/src/**.cpp",
		'components/' .. name .. "/src/**.cc",
		'components/' .. name .. "/src/**.h",
		'components/' .. name .. "/include/**.h",
		"client/common/StdInc.cpp",
		"client/common/Error.cpp"
	}

	vpaths { ["z/common/*"] = "client/common/**", ["z/*"] = "components/" .. name .. "/component.rc", ["*"] = "components/" .. name .. "/**" }

	defines { "COMPILING_" .. name:upper():gsub('-', '_'), 'HAS_LOCAL_H' }

	links { "Shared", "CitiCore" }

	pchsource "client/common/StdInc.cpp"
	pchheader "StdInc.h"

	-- add dependency requirements
	for dep, data in pairs(hasDeps) do
		configuration {}

		if not data.vendor or not data.vendor.dummy then
			links { dep }
		end

		if data.vendor then
			if data.vendor.include then
				data.vendor.include()
			end
		else
			includedirs { 'components/' .. dep .. '/include/' }
		end
	end

	configuration {}
	dofile('components/' .. name .. '/component.lua')

	-- loop again in case a previous file has set a configuration constraint
	for dep, data in pairs(hasDeps) do
		configuration {}

		if data.vendor then
			if data.vendor.depend then
				data.vendor.depend()
			end
		else
			dofile('components/' .. dep .. '/component.lua')
		end
	end

	configuration "windows"
		buildoptions "/MP"

		files {
			'components/' .. name .. "/component.rc",
		}

	configuration "not windows"
		files {
			'components/' .. name .. "/component.json"
		}

	filter { "system:not windows", "files:**/component.json" }
		buildmessage 'Copying %{file.relpath}'

		buildcommands {
			'{COPY} "%{file.relpath}" "%{cfg.targetdir}/lib' .. name .. '.json"'
		}

		buildoutputs {
			"%{cfg.targetdir}/lib" .. name .. ".json"
		}

	if not _OPTIONS['tests'] then
		return
	end

	-- test project
	local f = io.open('components/' .. name .. '/tests/main.cpp')

	if f then
		io.close(f)
	end

	if not f then
		return
	end

	project('tests_' .. name)

	language "C++"
	kind "ConsoleApp"

	includedirs { 'components/' .. name .. "/include/" }
	files { 'components/' .. name .. "/tests/**.cpp", 'components/' .. name .. "/tests/**.h", "client/common/StdInc.cpp" }

	if not f then
		files { "tests/test.cpp" }
	end

	links { "Shared", "CitiCore", "gmock_main", "gtest_main", name }

	pchsource "client/common/StdInc.cpp"
	pchheader "StdInc.h"
end

do_components = function()
	for _, comp in ipairs(components) do
		if not comp.dummy then
			do_component(comp.rawName, comp)
		end
	end
end

do_vendor = function()
	for _, comp in ipairs(components) do
		if comp.vendor and comp.vendor.run and comp.tagged then
			project(comp.rawName)

			if comp.vendor.include then
				comp.vendor.include()
			end

			comp.vendor.run()
		end
	end
end