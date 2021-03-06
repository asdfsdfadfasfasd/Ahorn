using ZipFile

function getAhornModDirs()
    if !get(config, "load_plugins_ahorn", true)
        return String[]
    end

    modsPath = joinpath(storageDirectory, "plugins")
    targetFolders = String[]

    if isdir(modsPath)
        for fn in readdir(modsPath)
            if isdir(joinpath(modsPath, fn))
                push!(targetFolders, joinpath(modsPath, fn))
            end
        end
    end

    return targetFolders
end

function getAhornModZips()
    if !get(config, "load_plugins_ahorn_zip", true)
        return String[]
    end

    modsPath = joinpath(storageDirectory, "plugins")
    targetFolders = String[]

    if isdir(modsPath)
        for fn in readdir(modsPath)
            if isfile(joinpath(modsPath, fn)) && hasExt(fn, ".zip")
                push!(targetZips, joinpath(modsPath, fn))
            end
        end
    end

    return targetFolders
end

function getCelesteModDirs()
    if !get(config, "load_plugins_celeste", true)
        return String[]
    end

    celesteDir = get(config, "celeste_dir", "")
    modsPath = joinpath(celesteDir, "Mods")

    targetFolders = String[]

    if isdir(modsPath)
        for fn in readdir(modsPath)
            if isdir(joinpath(modsPath, fn))
                push!(targetFolders, joinpath(modsPath, fn))
            end
        end
    end

    return targetFolders
end

function getModRoot(fn::String)
    celesteDir = get(config, "celeste_dir", "")
    modsPath = normpath(joinpath(celesteDir, "Mods"))

    path = normpath(fn)

    while true
        parent = dirname(path)

        if parent == modsPath
            if isdir(path)
                return true, path

            else
                return true, parent
            end
        end

        if path == parent
            return false, ""
        end

        path = parent
    end
end

function getCelesteModZips()
    if !get(config, "load_plugins_celeste_zip", true)
        return String[]
    end

    celesteDir = get(config, "celeste_dir", "")
    modsPath = joinpath(celesteDir, "Mods")

    targetZips = String[]

    if isdir(modsPath)
        for fn in readdir(modsPath)
            if isfile(joinpath(modsPath, fn)) && hasExt(fn, ".zip")
                push!(targetZips, joinpath(modsPath, fn))
            end
        end
    end

    return targetZips
end

function findExternalSprite(resource::String, atlas::String="Gameplay")
    targetFolders = getCelesteModDirs()
    targetZips = getCelesteModZips()
    atlasPath = joinpath("Graphics", "Atlases", atlas)

    for target in targetFolders
        fn = joinpath(target, atlasPath, resource * ".png")
        if isfile(fn)
            return fn
        end
    end

    # ZipFile uses unix paths
    gameplayUnixPath = replace(atlasPath, "\\" => "/")

    for target in targetZips
        fn = gameplayUnixPath * "/" * resource * ".png"
        zipfh = ZipFile.Reader(target)

        for file in zipfh.files
            if file.name == fn
                return target
            end
        end

        close(zipfh)
    end
end

const warnedFilenames = Set{String}()

function warnBadExtensions(fixable::Array{String, 1}, nonFixable::Array{String, 1}, correctExt::String)
    res = false

    fixable = String[fn for fn in fixable if !(fn in warnedFilenames)]
    nonFixable = String[fn for fn in nonFixable if !(fn in warnedFilenames)]

    if !isempty(fixable)
        fixableCount = length(fixable)
        plural = fixableCount == 1 ? "" : "s"
        dialogText = "You have $fixableCount image$plural with bad extension$plural.\n" *
            "These are not loadable by Celeste (Everest).\n" * 
            "Do you want to rename them?\n\n" *
            join(fixable, "\n")
        confirmed = ask_dialog(dialogText, Ahorn.window)
        res = confirmed

        if confirmed
            for fn in fixable
                path, ext = splitext(fn)
                out = path * correctExt
                tmp = out * ".tmp"

                # Workaround for Windows...
                mv(fn, tmp)
                mv(tmp, out)
            end

        else
            push!(warnedFilenames, fixable...)
        end
    end

    if !isempty(nonFixable)
        nonFixableCount = length(nonFixable)
        plural = nonFixableCount == 1 ? "" : "s"
        dialogText = "You have $nonFixableCount file$plural with bad extension$plural that cannot be automatically fixed.\n" *
            "These are not loadable by Celeste (Everest) or Ahorn.\n" * 
            "Please rename the file$plural manually with the proper extension '$correctExt' or contact the mod maker.\n\n" * 
            join(nonFixable, "\n")
        info_dialog(dialogText, Ahorn.window)

        push!(warnedFilenames, nonFixable...)
    end

    return res
end

const spriteZipCache = Dict{String, Any}()

# Resource prefix filters uneeded files, uses unix paths
function cacheZipContent(filename::String, resourcePrefix::String="Graphics/Atlases/Gameplay/")
    debug.log("Caching zip content for $filename", "ZIP_CACHING_VERBOSE")

    spriteZipCache[filename] = Dict{String, Any}()

    # Always uses Unix path
    zipfh = ZipFile.Reader(filename)

    for file in zipfh.files
        if startswith(file.name, resourcePrefix)
            parts = split(file.name, "/")
            atlas = parts[3]
            resource = join(parts[3:end], "/")

            if hasExt(file.name, ".png")
                spriteZipCache[filename][resource] = Cairo.read_from_png(file)

            elseif hasExt(file.name, ".meta.yaml")
                try
                    spriteZipCache[filename][resource] = YAML.load(String(read(file)))

                catch
                    # Bad yaml file
                end
            end
        end
    end
    
    close(zipfh)
end

# Cleanup and destroy surfaces
function uncacheZipContent(filename::String)
    debug.log("Uncaching zip content for $filename", "ZIP_CACHING_VERBOSE")

    fileCache = get(spriteZipCache, filename, nothing)

    if fileCache !== nothing
        for (resource, data) in fileCache
            if hasExt(resource, ".png")
                deleteSurface(data)
            end
        end
    end
end

function findExternalSpritesInZip(filename::String, atlasesPath::String, atlasesUnixPath::String, badExt::Array{String, 1}, allowRetry::Bool=true)
    res = Tuple{String, String, String}[]
    fileCache = get(spriteZipCache, filename, nothing)

    if fileCache !== nothing
        for (resource, data) in fileCache
            if hasExt(resource, ".png")
                if !hasExt(resource, ".png", false)
                    # Case sensitive check for warnings
                    push!(badExt, resource)
                end

                parts = split(resource, "/")
                atlas = parts[1]
                resourceNoAtlas = join(parts[2:end], "/")

                push!(res, (resourceNoAtlas, filename, atlas))
            end
        end

    else
        if allowRetry
            cacheZipContent(filename)

            return findExternalSpritesInZip(filename, atlasesPath, atlasesUnixPath, badExt, false)
        
        else
            return res
        end
    end

    return res
end

function findExternalSpritesInFolder(filename::String, atlasesPath::String, badExt::Array{String, 1}, targetAtlases::Array{String, 1}=["Gameplay"])
    res = Tuple{String, String, String}[]
    atlasPath = joinpath(filename, atlasesPath)

    if !isdir(atlasPath)
        return res
    end

    for atlas in readdir(atlasPath)
        if !(atlas in targetAtlases)
            continue
        end

        path = joinpath(atlasPath, atlas)

        if isdir(path)
            for (root, dir, files) in walkdir(path)
                for file in files
                    if hasExt(file, ".png")
                        if !hasExt(file, ".png", false)
                            # Case sensitive check for warnings
                            push!(badExt, joinpath(root, file))
                        end

                        rawpath = joinpath(root, file)
                        push!(res, (relpath(rawpath, path), rawpath, atlas))
                    end
                end
            end
        end
    end

    return res
end

function findAllExternalSprites()
    warnOnBadExts = get(config, "prompt_bad_resource_exts", true)
    res = Tuple{String, String, String}[]

    folderFileBadExt = String[]
    zipFileBadExt = String[]
    
    targetFolders = getCelesteModDirs()
    targetZips = getCelesteModZips()
    atlasesPath = joinpath("Graphics", "Atlases")

    # ZipFile uses unix paths
    atlasesUnixPath = replace(atlasesPath, "\\" => "/")

    for target in targetFolders
        append!(res, findExternalSpritesInFolder(target, atlasesPath, folderFileBadExt))
    end

    for target in targetZips
        append!(res, findExternalSpritesInZip(target, atlasesPath, atlasesUnixPath, zipFileBadExt))
    end

    if warnOnBadExts
        confirmed = warnBadExtensions(folderFileBadExt, zipFileBadExt, ".png")

        if confirmed
            return findAllExternalSprites()
        end
    end
    
    return res
end

function findChangedExternalSprites()
    warnOnBadExts = get(config, "prompt_bad_resource_exts", true)
    res = Tuple{String, String, String}[]

    changedFilenames = FileWatcher.processWatchEvents(FileWatcher.basePath)

    folderFileBadExt = String[]
    zipFileBadExt = String[]

    # ZipFile uses unix paths
    atlasesPath = joinpath("Graphics", "Atlases")
    atlasesUnixPath = replace(atlasesPath, "\\" => "/")

    for filename in changedFilenames
        if hasExt(filename, ".zip")
            append!(res, findExternalSpritesInZip(filename, atlasesPath, atlasesUnixPath, zipFileBadExt))

        elseif hasExt(filename, ".png")
            hasModRoot, modRoot = getModRoot(filename)

            if hasModRoot
                relative = relpath(filename, modRoot)
                parts = splitpath(relative)

                if parts[1] == "Graphics" && parts[2] == "Atlases"
                    push!(res, (joinpath(parts[4:end]...), filename, parts[3]))
                end
            end
        end
    end

    if warnOnBadExts
        confirmed = warnBadExtensions(folderFileBadExt, zipFileBadExt, ".png")

        if confirmed
            return findChangedExternalSprites()
        end
    end

    return res
end

function loadLangdata()
    targetFolders = joinpath.(getCelesteModDirs(), "Ahorn")
    targetZips = getCelesteModZips()

    lang = get(config, "language", "en_gb")
    internalFilename = abspath("../lang/$lang.lang")

    res = parseLangfile(String(read(internalFilename)))

    for folder in targetFolders
        fn = joinpath(folder, "lang", "$(lang).lang")
        if ispath(fn)
            content = String(read(fn))
            parseLangfile(content, init=res)
        end
    end

    for fn in targetZips
        zipfh = ZipFile.Reader(fn)
        
        for file in zipfh.files
            name = file.name
            path, fnext = splitext(name)

            if path == "Ahorn/lang/$(lang)" && hasExt(name, ".lang")
                content = String(read(file))
                parseLangfile(content, init=res)
            end
        end

        close(zipfh)
    end

    return res
end

function findExternalModules(args::String...)
    res = String[]

    targetFolders = vcat(
        joinpath.(getCelesteModDirs(), "Ahorn"),
        getAhornModDirs()
    )

    for folder in targetFolders
        path = joinpath(folder, args...)
        if isdir(path)
            for file in readdir(path)
                if hasExt(file, ".jl")
                    push!(res, joinpath(path, file))
                end
            end
        end
    end

    return res
end

function loadExternalModules!(loadedModules::Dict{String, Module}, loadedNames::Array{String, 1}, args::String...)
    # ZipFile uses unix paths 
    path = joinpath("Ahorn", args...)
    path = replace(path, "\\" => "/")

    targets = vcat(
        getCelesteModZips(),
        getAhornModZips()
    )

    for target in targets
        zipfh = ZipFile.Reader(target)

        for file in zipfh.files
            name = file.name

            if startswith(name, path) && file.uncompressedsize > 0
                # Add .from_zip to the filename
                # Prevents hotswaping from trying to access invalid file
                fakeFn = name * ".from_zip"

                try
                    content = String(read(file))
                    loadedModules[fakeFn] = eval(Meta.parse(content))

                    if !(fakeFn in loadedNames)
                        push!(loadedNames, fakeFn)
                    end

                catch e
                    println(Base.stderr, "! Failed to load \"$name\" from \"$target\"")
                    println(Base.stderr, e)
                end
            end
        end

        close(zipfh)
    end
end