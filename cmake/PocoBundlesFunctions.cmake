macro(LOG_DEBUG log_msg)
#	message(STATUS "DEBUG    ${log_msg}")
endmacro()

macro(LOG_VERBOSE log_msg)
#	message(STATUS "${log_msg}")
	log_debug(${log_msg})
endmacro()


macro(COPY_TO_DESTINATION file var_dest_file var_code_list)
	file(INSTALL "${file}" DESTINATION "${DESTINATION}")
	get_filename_component(filename "${file}" NAME)
	set(${var_dest_file} "${DESTINATION}/${filename}")
	list(APPEND ${var_code_list} ${${var_dest_file}})
endmacro()

macro(GET_ALIASES file var_real_file var_aliases)
	get_filename_component(${var_real_file} "${file}" REALPATH)
	if(NOT "${${var_real_file}}" STREQUAL "${file}")
		list(APPEND ${var_aliases} ${file})
	endif()
	get_filename_component(filename_WE ${file} NAME_WE)
	get_filename_component(dir ${file} PATH)
	file(GLOB alias_candidates ${dir}/${filename_WE}*)
	list(REMOVE_ITEM alias_candidates ${${var_real_file}})
	foreach(alias_candidate ${alias_candidates})
		get_filename_component(alias_resolved ${alias_candidate} REALPATH)
		if(${alias_resolved} STREQUAL ${${var_real_file}})
			list(APPEND ${var_aliases} ${alias_candidate})
		endif()
	endforeach()
	if(${var_aliases})
		list(REMOVE_DUPLICATES ${var_aliases})
	endif()
endmacro()

macro(IS_SYMLINK file var_result)
	get_filename_component(absoulute_path "${file}" ABSOLUTE)
	get_filename_component(real_path "${file}" REALPATH)
	if(NOT "${absoulute_path}" STREQUAL "${real_path}")
		set(${var_result} true)
	else()
		set(${var_result} false)
	endif()
endmacro()

macro(FIND_LIBRARY_IN_BUNDLE_DEPENDENCIES library var_result)
	unset(${var_result})
	foreach(bundle ${BUNDLE_DEPS})
		list(FIND ${bundle}_LIBRARIES ${library} index)
		if(index GREATER -1)
			set(${var_result} ${bundle})
			break()
		endif()
	endforeach()
endmacro()


# -- build an xml tag
# usage: xml(VAR foo bar) --> VAR = "<foo>bar</foo>"
macro(XML VAR_ELEMENT TAG_NAME CONTENT)
	set(${VAR_ELEMENT} <${TAG_NAME}>${CONTENT}</${TAG_NAME}>)
endmacro()

# -- convert a cmake list to a comma delineated string
# usage: list_to_comma_separated(VAR ${list} [..])
macro(LIST_TO_COMMA_SEPARATED VAR_NAME)
	set(${VAR_NAME} ${ARGV1})
	if(${ARGC} GREATER 2)
		list(APPEND remaining_args ${ARGN})
		list(REMOVE_AT remaining_args 0)
		foreach(arg ${remaining_args}) 
			set(${VAR_NAME} ${${VAR_NAME}},${arg})
		endforeach()
	endif()
endmacro()

macro(SPLIT str sep var_head var_tail)
	string(LENGTH "${str}" length)
	if(length GREATER 0)
		string(FIND "${str}" "${sep}" index)
		if(${index} GREATER -1)
			string(SUBSTRING "${str}" 0 ${index} ${var_head})
			math(EXPR index ${index}+1)
			string(SUBSTRING "${str}" ${index} -1 ${var_tail})
		else()
			set(${var_head} "${str}")
			unset(${var_tail})
		endif()
	else()
		unset(${var_head})
		unset(${var_tail})
	endif()	
endmacro()

macro(BUNDLE_KEY bundle key_var)
	string(TOUPPER ${bundle} TEMP)
    string(REPLACE "." "_" ${key_var} ${TEMP})
    unset(TEMP)
endmacro()

macro(LIBRARY_KEY library key_var)
	#get_filename_component(lib_file "${library}" REALPATH)
	get_filename_component(lib_file_name ${library} NAME)
	string(TOUPPER ${lib_file_name} TEMP)
    string(REPLACE "." "_" ${key_var} ${TEMP})
    unset(TEMP)
    #unset(lib_file)
endmacro()

# script that fixes up a poco osp bundle's libraries
# Call with the following definitions:
#  DESTINATION set to the directory that the libraries will be copied to.
#  LIBRARIES set to a list of library names to be copied to and fixed up in the bundle.
#  <NAME>_FILE set to that library's full path to main file ($<TARGET_FILE:...>)
#  BUNDLE_DEPS set to a list of names of dependent bundles.
#  <BUNDLE_NAME>_LIBRARIES set to that bundle's contained libraries.
#  CONFIGURATION set to the current build configuration ($<CONFIGURATION>)
function(POCO_FIXUP_LIBRARIES bundle)
	## generate a unique key (toupper from the bundle name)
	bundle_key(${bundle} BUNDLE)
	set(mapping_file ${${BUNDLE}_POCO_BUNDLE_MAPPING_FILE})
	file(WRITE ${mapping_file} "#This is a mapping file for bundle ${bundle} ${BUNDLE}.\n")
	file(APPEND ${mapping_file} "set(${BUNDLE}_NAME ${bundle})\n")
	set(lib_location "lib")
	set(destination ${${BUNDLE}_POCO_BUNDLE_ROOT}/${lib_location})
	if(APPLE) ## get install_name_tool executable
		find_program(INSTALL_NAME_TOOL NAME install_name_tool HINTS /usr/bin /usr/local/bin)
    	if(NOT INSTALL_NAME_TOOL) 
    		message(FATAL_ERROR "install_name_tool not found")
    	endif()
    endif()
    # gather all required libraries and their prerequisites
    include(GetPrerequisites)
	foreach(lib ${${BUNDLE}_POCO_BUNDLE_LIBRARIES})
		if(NOT ${lib}_FILE)
			message(FATAL_ERROR "_FILE not defined for lib: ${lib}")
		endif()
		get_filename_component(lib_real_file "${${lib}_FILE}" REALPATH)
		library_key(${lib_real_file} key)
		get_filename_component(${key}_SOURCE_DIRECTORY "${${lib}_FILE}" PATH)
		
		## overrides to spoof file location and type for ignored or already included bundle libraries.
		function(gp_resolve_item_override context item exepath dirs resolved_item_var)
			if(resolved)
			#	return()
			endif()
			log_debug("---- gp_resolve_item_override")
			log_debug(" ${CMAKE_CURRENT_LIST_FILE}:${CMAKE_CURRENT_LIST_LINE}")
			log_debug("CONTEXT: ${context}")
			log_debug("ITEM: ${item}")
			log_debug("EXEPATH: ${exepath}")
			log_debug("DIRS: ${dirs}")
			log_debug("${resolved_item_var}: ${${resolved_item_var}}")
			library_key(${item} item_key) # get key for item
			if(${${item_key}_MAPPING}_BUNDLE)
				set(${resolved_item_var} ${${${item_key}_MAPPING}_SOURCE_FILE} PARENT_SCOPE)
				set(resolved TRUE PARENT_SCOPE)
				log_debug("Bundle-item '${item}' with Key ${item_key} already found in Bundle ${${${item_key}_BUNDLE}} and will be skipped.")
			elseif(${item_key}_IGNORE OR ${item}_IGNORE)
				set(${resolved_item_var} "${${key}_SOURCE_DIRECTORY}/${item}" PARENT_SCOPE) # spoofing as a local type
				set(resolved TRUE PARENT_SCOPE)
				log_debug("Bundle-item '${item}' with Key ${item_key} is on ignore list. Probably a dynamic library that will be provided during runtime.")
			else()
				log_debug("Bundle-item '${item}' with Key ${item_key} not on ignore list or in other bundle. Resolved: ${resolved} ${${resolved_item_var}}")
			endif()
		endfunction()

		function(gp_resolved_file_type_override file type_var)
			log_debug("----- gp_resolved_file_type")
			log_debug(" ${CMAKE_CURRENT_LIST_FILE}:${CMAKE_CURRENT_LIST_LINE}")
			log_debug("FILE: ${file}")
			log_debug("${type_var}: ${${type_var}}")
			library_key(${file} item_key) # get key for item
			if(${${item_key}_MAPPING}_BUNDLE)
				set(${type_var} system PARENT_SCOPE)
				log_debug("Bundle-item '${item}' with Key ${item_key} already found in Bundle ${${${item_key}_BUNDLE}_NAME}. Setting resolved type to system.")
			elseif(${item_key}_IGNORE OR ${item}_IGNORE)
				log_debug("Bundle-item '${item}' with Key ${item_key} is on ignore list. Setting resolved type to system.")
				set(${type_var} system PARENT_SCOPE)
			else()
				log_debug("Bundle-item '${item}' with Key ${item_key} not on ignore list or in other bundle. Setting resolved type to ${${type_var}}.")
			endif()
		endfunction()

		message("GP_RESOLVE_ITEM(${${lib}_FILE} ${${lib}_FILE} ${${lib}_FILE} ${${key}_SOURCE_DIRECTORY} ${key}_resolved)")
		GP_RESOLVE_ITEM(${${lib}_FILE} ${${lib}_FILE} ${${lib}_FILE} ${${key}_SOURCE_DIRECTORY} ${key}_resolved)
		get_prerequisites(${${lib}_FILE} ${key}_prereqs 1 0 "" "${${key}_SOURCE_DIRECTORY}")
		list(APPEND libraries ${${lib}_FILE} ${${key}_prereqs})
		message(STATUS "${key} ${${lib}_FILE} PREREQS: ${${key}_prereqs}")
		message(STATUS "${${key}_SOURCE_DIRECTORY}")
		message(STATUS "${key}_resolved: ${${key}_resolved}")
	endforeach()
	list(REMOVE_DUPLICATES libraries)
	log_debug("${libraries}")

	# generate keys and alias mappings
	foreach(lib_file ${libraries})
		if(IS_ABSOLUTE ${lib_file})
			log_verbose("Preparing ${lib_file}")
			get_filename_component(lib_real_file "${lib_file}" REALPATH)
			library_key(${lib_real_file} key)
			log_verbose(" Library key ${key}")
			# handle symlinks
			#is_symlink(${${lib}_FILE} file_is_symlink)
			get_aliases(${lib_file} ${key}_SOURCE_FILE ${key}_ALIASES)
			get_filename_component(${key}_SOURCE_FILE_NAME "${${key}_SOURCE_FILE}" NAME)
			get_filename_component(${key}_SOURCE_DIRECTORY "${${key}_SOURCE_FILE}" PATH)
			set(${key}_SOURCE_LINK_NAME "${lib_file}")
			set(${key}_DEST_FILE_NAME "${${key}_SOURCE_FILE_NAME}")
			#set(${key}_DEST_LINK_NAME "@loader_path/../MacOS/codeCache/${${key}_DEST_FILE_NAME}")
			#set(${key}_DEST_LINK_NAME "@executable_path/codeCache/${${key}_DEST_FILE_NAME}")
			if(APPLE)
				if(${lib_file} MATCHES "(dylib)$")
					# determine the link name of the library (its id)
					execute_process(COMMAND otool -D ${lib_file}
						COMMAND tail -n 1 # only get the second line of output
						OUTPUT_VARIABLE ${key}_SOURCE_LINK_NAME
						OUTPUT_STRIP_TRAILING_WHITESPACE
					)		
					log_debug("Lib id: ${${key}_SOURCE_LINK_NAME}")	
					get_filename_component(${key}_SO_NAME "${${key}_SOURCE_LINK_NAME}" NAME)
					if(NOT ${key}_SOURCE_FILE_NAME STREQUAL ${key}_SO_NAME)
						set(${key}_DEST_FILE_NAME ${${key}_SO_NAME})
					endif()
				endif()
			endif()
			foreach(alias ${${key}_ALIASES} ${${key}_SOURCE_FILE})
				library_key(${alias} alias_key)
				set(${alias_key}_MAPPING ${key})
				set(${alias_key}_MAPPING ${key} PARENT_SCOPE)
				log_debug(" ${alias_key}_MAPPING: ${${alias_key}_MAPPING}")
				file(APPEND ${mapping_file} "\nset(${alias_key}_MAPPING ${key})")
				log_verbose(" Added alias ${alias_key}: ${alias}")
			endforeach()
			list(APPEND bundled_lib_keys ${key})
		endif()
	endforeach()

	# generate list of library files to copy to the bundle
#	foreach(key ${library_keys})
#		get_filename_component(${key_in_bundle}_SOURCE_FILE "${library}" ABSOLUTE)
#		get_filename_component(${key_in_bundle}_SOURCE_FILE_NAME "${library}" NAME)
#		set(${key_in_bundle}_SOURCE_LINK_NAME ${library})
#		set(${key_in_bundle}_DEST_FILE_NAME "${${key_in_bundle}_SOURCE_FILE_NAME}")
#		set(${key_in_bundle}_DEST_LINK_NAME "${${key_in_bundle}_DEST_FILE_NAME}")
#		list(APPEND bundled_lib_keys ${key_in_bundle})
#		list(APPEND ${${key}_MAPPING}_PREREQUISITES_KEYS ${key_in_bundle})
#		endforeach()
#	endforeach()
	list(REMOVE_DUPLICATES bundled_lib_keys)
	foreach(key ${bundled_lib_keys})
		if(${${key}_MAPPING}_BUNDLE)
			log_verbose("found ${key} in ${${key}_BUNDLE}, not moving to bundle ${BUNDLE}")
			list(APPEND remove_keys ${key})
		endif()
		if(NOT EXISTS ${${key}_SOURCE_FILE})
			log_verbose("No source file for Key ${key} found at ${${key}_SOURCE_FILE} ")
			list(APPEND remove_keys ${key})
		endif()
	endforeach()
	if(remove_keys)
		list(REMOVE_ITEM bundled_lib_keys ${remove_keys})
	endif()

	log_verbose("Keys that will be added to bundle: ${bundled_lib_keys}")
	log_verbose("Keys that will be omitted: ${remove_keys}")
	foreach(key ${bundled_lib_keys})
		# copy the library to the destination directory. (BUNDLE_ROOT/lib)
		set(${key}_DEST_FILE ${destination}/${${key}_DEST_FILE_NAME})
		configure_file(${${key}_SOURCE_FILE} ${${key}_DEST_FILE} COPYONLY)
		#file(INSTALL "${${key}_SOURCE_FILE}" DESTINATION "${destination}")
		#if(NOT ${key}_SOURCE_FILE_NAME STREQUAL ${key}_DEST_FILE_NAME)
			#file(RENAME "${destination}/${${key}_SOURCE_FILE_NAME}" "${${key}_DEST_FILE_NAME}")
		#endif()
		file(RELATIVE_PATH code_entry ${${BUNDLE}_POCO_BUNDLE_ROOT} ${${key}_DEST_FILE})
		list(APPEND code ${code_entry})
	endforeach()

	if(APPLE)
		foreach(key ${bundled_lib_keys})
			log_debug("${key}_PREREQUISITES_KEYS: ${${key}_PREREQUISITES_KEYS}")
			log_verbose("Changing install names for ${key}")
			unset(install_name_tool_args)
			foreach(prereq ${${key}_prereqs})
				library_key(${prereq} _key)
				if(${_key}_MAPPING)
					set(prereq_key ${${_key}_MAPPING})
				else()
					set(prereq_key ${_key})
				endif()
				log_verbose("${_key} ${prereq_key} ${${prereq_key}_DEST_LINK_NAME}")
				if(${prereq_key}_DEST_LINK_NAME)
					# the prereq was already renamed, by another bundle possibly.
					log_verbose(" D ${prereq} -> ${${prereq_key}_DEST_LINK_NAME}")
					execute_process(COMMAND ${INSTALL_NAME_TOOL} -change "${prereq}" "${${prereq_key}_DEST_LINK_NAME}" "${${key}_DEST_FILE}")
				else()
					if(NOT IS_ABSOLUTE ${prereq})
						# see if the name starts with a @rpath, @executable_path or @loader_path
						if(${prereq} MATCHES "^(@rpath|@executable_path|@loader_path)")
							message(STATUS "${prereq} is portable dyld, that's fine.")
						else()
							message(FATAL_ERROR "${prereq} has no absolute path.")
						endif()
						#log_verbose(" ${prereq} -> @loader_path/../MacOS/${prereq}")
						#execute_process(COMMAND ${INSTALL_NAME_TOOL} -change "${prereq}" "@loader_path/../MacOS/${prereq}" "${${key}_DEST_FILE}")
						#log_verbose(" ${prereq} -> @executable_path/${prereq}")
						#set(${prereq_key}_DEST_LINK_NAME @executable_path/${prereq})
						#execute_process(COMMAND ${INSTALL_NAME_TOOL} -change "${prereq}" "@executable_path/${prereq}" "${${key}_DEST_FILE}")
					endif()
				endif()
			endforeach()
			if(${key}_DEST_LINK_NAME)
				execute_process(COMMAND ${INSTALL_NAME_TOOL} -id "${${key}_DEST_LINK_NAME}" "${${key}_DEST_FILE}")
			endif()
			execute_process(COMMAND ${INSTALL_NAME_TOOL} 
				-add_rpath "@loader_path/." # this allows the library to find other libs in the bundle cache directory
				"${${key}_DEST_FILE}"
			)
			
		endforeach()
	endif()
	# handle debug symbols for win32 dlls
	if("${CONFIGURATION}" STREQUAL Debug)
		if(WIN32)
			foreach(key ${bundled_lib_keys})
			string(REPLACE ".dll" ".pdb" ${key}_PDB_FILE "${${key}_SOURCE_FILE}")
			if(EXISTS ${${key}_PDB_FILE})
				log_debug("PDB file for ${key}: ${${key}_PDB_FILE}")
				file(INSTALL "${${key}_PDB_FILE}" DESTINATION "${destination}")
				get_filename_component(${key}_PDB_FILE_NAME ${${key}_PDB_FILE} NAME)
				list(APPEND code ${lib_location}/${${key}_PDB_FILE_NAME})
			else()
				message(WARNING "Debug symbols for ${key} not found.")
			endif()
			endforeach()
		endif()
	endif()
	# write mappings to file 
	# add dependencies to own mapping file to support transitive lookup of mappings
	foreach(other_mapping_file ${${BUNDLE}_INCLUDED_MAPPINGS})
		file(APPEND ${mapping_file} "\ninclude(\"${other_mapping_file}\")")
	endforeach()
	foreach(key ${bundled_lib_keys})
		file(APPEND ${mapping_file} "\nset(${key}_SOURCE_LINK_NAME \"${${key}_SOURCE_LINK_NAME}\")")
		file(APPEND ${mapping_file} "\nset(${key}_SOURCE_DIRECTORY \"${${key}_SOURCE_DIRECTORY}\")")
		file(APPEND ${mapping_file} "\nset(${key}_SOURCE_FILE_NAME \"${${key}_SOURCE_FILE_NAME}\")")
		file(APPEND ${mapping_file} "\nset(${key}_SOURCE_FILE \"${${key}_SOURCE_FILE}\")")
		file(APPEND ${mapping_file} "\nset(${key}_DEST_FILE_NAME \"${${key}_DEST_FILE_NAME}\")")
		file(APPEND ${mapping_file} "\nset(${key}_DEST_FILE \"${${key}_DEST_FILE}\")")
		file(APPEND ${mapping_file} "\nset(${key}_DEST_LINK_NAME \"${${key}_DEST_LINK_NAME}\")")
		file(APPEND ${mapping_file} "\nset(${key}_BUNDLE ${BUNDLE})")
		set(${key}_DEST_FILE ${${key}_DEST_FILE} PARENT_SCOPE)
		set(${key}_DEST_FILE_NAME ${${key}_DEST_FILE_NAME} PARENT_SCOPE)
	endforeach()

	set(${BUNDLE}_POCO_BUNDLE_CODE ${${BUNDLE}_POCO_BUNDLE_CODE} ${code} PARENT_SCOPE)
	log_debug("Appended to ${BUNDLE}_POCO_BUNDLE_CODE: ${code}")
endfunction()

function(POCO_SET_ACTIVATOR bundle library)
	bundle_key(${bundle} BUNDLE)
	library_key(${${library}_FILE} key)
	log_debug("key: ${key}")
	set(key ${${key}_MAPPING})
	log_debug("key: ${key}")
	set(full_filename ${${key}_DEST_FILE_NAME})
	string(REGEX REPLACE "d?\\.(dll|so|dylib)$" "" activator "${full_filename}")
	set(${BUNDLE}_POCO_BUNDLE_ACTIVATOR_LIBRARY ${activator} PARENT_SCOPE)
	log_debug("Set ${BUNDLE}_POCO_BUNDLE_ACTIVATOR_LIBRARY: ${activator} from ${${key}_DEST_FILE_NAME}")
endfunction()

function(POCO_COPY_FILES_TO_BUNDLE bundle file location_in_bundle)
	bundle_key(${bundle} BUNDLE)
	get_filename_component(filename "${file}" NAME)
	set(destination "${${BUNDLE}_POCO_BUNDLE_ROOT}/${location_in_bundle}")
	file(INSTALL "${file}" DESTINATION "${destination}")
	list(APPEND files_in_bundle "${location_in_bundle}/${filename}")
	set(${BUNDLE}_POCO_BUNDLE_FILES ${${BUNDLE}_POCO_BUNDLE_FILES} ${files_in_bundle} PARENT_SCOPE)
	log_debug("Appended to ${BUNDLE}_POCO_BUNDLE_FILES: ${files_in_bundle}")
endfunction()

function(POCO_CONFIGURE_BUNDLE_SPEC bundle input output)
	bundle_key(${bundle} BUNDLE)
	set(POCO_BUNDLE_SYMBOLIC_NAME ${${BUNDLE}_POCO_BUNDLE_SYMBOLIC_NAME})
	set(POCO_BUNDLE_NAME ${${BUNDLE}_POCO_BUNDLE_NAME})
	set(POCO_BUNDLE_VERSION ${${BUNDLE}_POCO_BUNDLE_VERSION})
	log_verbose("Configuring bundle specification for ${BUNDLE}")
	# build all xml tags
if(${BUNDLE}_POCO_BUNDLE_VENDOR)
	xml(POCO_BUNDLE_VENDOR_ELEMENT vendor ${${BUNDLE}_POCO_BUNDLE_VENDOR})
	log_debug("${POCO_BUNDLE_VENDOR_ELEMENT}")
else()
	log_debug("No vendor.")
endif()
if(${BUNDLE}_POCO_BUNDLE_COPYRIGHT)
	xml(POCO_BUNDLE_COPYRIGHT_ELEMENT copyright ${${BUNDLE}_POCO_BUNDLE_COPYRIGHT})
	log_debug("${POCO_BUNDLE_COPYRIGHT_ELEMENT}")
else()
	log_debug("No copyright.")
endif()
if(${BUNDLE}_POCO_BUNDLE_ACTIVATOR_CLASS AND ${BUNDLE}_POCO_BUNDLE_ACTIVATOR_LIBRARY)
	xml(POCO_BUNDLE_ACTIVATOR_CLASS_ELEMENT class ${${BUNDLE}_POCO_BUNDLE_ACTIVATOR_CLASS})
	xml(POCO_BUNDLE_ACTIVATOR_LIBRARY_ELEMENT library ${${BUNDLE}_POCO_BUNDLE_ACTIVATOR_LIBRARY})
	xml(POCO_BUNDLE_ACTIVATOR_ELEMENT activator "${POCO_BUNDLE_ACTIVATOR_CLASS_ELEMENT}${POCO_BUNDLE_ACTIVATOR_LIBRARY_ELEMENT}")
	log_debug("${POCO_BUNDLE_ACTIVATOR_ELEMENT}")
else()
	log_debug("No activator. ${${BUNDLE}_POCO_BUNDLE_ACTIVATOR_CLASS} ${${BUNDLE}_POCO_BUNDLE_ACTIVATOR_LIBRARY}")
endif()
if(${BUNDLE}_POCO_BUNDLE_LAZY_START)
	xml(POCO_BUNDLE_LAZY_START_ELEMENT lazyStart ${${BUNDLE}_POCO_BUNDLE_LAZY_START})
	log_debug("${POCO_BUNDLE_LAZY_START_ELEMENT}")
else()
	log_debug("No lazyStart.")
endif()
if(${BUNDLE}_POCO_BUNDLE_RUN_LEVEL)
	xml(POCO_BUNDLE_RUN_LEVEL_ELEMENT runLevel ${${BUNDLE}_POCO_BUNDLE_RUN_LEVEL})
	log_debug("${POCO_BUNDLE_RUN_LEVEL_ELEMENT}")
else()
	log_debug("No runLevel.")
endif()
if(${BUNDLE}_POCO_BUNDLE_DEPENDENCY)
	# workaround for cmake bug 9317 leading to erroneous list operations with square brackets
	# http://public.kitware.com/Bug/view.php?id=9317
	set(list_sep ",")
	set(dep_sep "@")
	split("${${BUNDLE}_POCO_BUNDLE_DEPENDENCY}" "${list_sep}" head tail)
	string(LENGTH "${head}" length)
	while(length GREATER 0)
		split("${head}" "${dep_sep}" depSymbolicName depVersion)
		split("${tail}" "${list_sep}" head tail)
		string(LENGTH "${head}" length)
		xml(DEPENDENCY_SYMBOLIC_NAME_ELEMENT symbolicName ${depSymbolicName})
		xml(DEPENDENCY_VERSION_ELEMENT version ${depVersion})
		xml(DEPENDENCY_ELEMENT dependency "${DEPENDENCY_SYMBOLIC_NAME_ELEMENT}${DEPENDENCY_VERSION_ELEMENT}")
		set(POCO_BUNDLE_DEPENDENCY_ELEMENT "${POCO_BUNDLE_DEPENDENCY_ELEMENT}${DEPENDENCY_ELEMENT}")
	endwhile()
	log_debug("${POCO_BUNDLE_DEPENDENCY_ELEMENT}")
else()
	log_debug("No dependency.")
endif()
if(${BUNDLE}_POCO_BUNDLE_EXTENDS)
	xml(POCO_BUNDLE_EXTENDS_ELEMENT extends ${${BUNDLE}_POCO_BUNDLE_EXTENDS})
	log_debug("${POCO_BUNDLE_EXTENDS_ELEMENT}")
else()
	log_debug("No extends.")
endif()
if(${BUNDLE}_POCO_BUNDLE_CODE)
	list_to_comma_separated(POCO_BUNDLE_CODE_COMMA_SEP ${${BUNDLE}_POCO_BUNDLE_CODE})
	xml(POCO_BUNDLE_CODE_ELEMENT code ${POCO_BUNDLE_CODE_COMMA_SEP})
	log_debug("${POCO_BUNDLE_CODE_ELEMENT}")
else()
	log_debug("No code.")
endif()
if(${BUNDLE}_POCO_BUNDLE_FILES)
	list_to_comma_separated(POCO_BUNDLE_FILES_COMMA_SEP ${${BUNDLE}_POCO_BUNDLE_FILES})
	xml(POCO_BUNDLE_FILES_ELEMENT files ${POCO_BUNDLE_FILES_COMMA_SEP})
	log_debug("${POCO_BUNDLE_FILES_ELEMENT}")
else()
	log_debug("No files.")
endif()

configure_file("${input}" "${output}")
message(STATUS "Bundle specification written to ${output}")
endfunction()