Set-Location ".\build"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function GenerateSha([string]$filePath,[string]$artifactsPath, [string]$shaFileName)
{
   $sha = (Get-FileHash $filePath).Hash.ToLower()
   $shaPath = Join-Path $artifactsPath "$shaFileName.sha"
   Out-File -InputObject $sha -Encoding ascii -FilePath $shaPath
   LogSuccess "Generating hash for $filePath"
}

function Unzip([string]$zipfilePath, [string]$outputpath) {
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfilePath, $outputpath)
        LogSuccess "Unzipped:$zipfilePath at $outputpath"
    }
    catch {
        LogErrorAndExit "Unzip failed for:$zipfilePath" $_.Exception
    }
}


function Zip([string]$directoryPath, [string]$zipPath) {
    try {
        LogSuccess "start zip:$directoryPath to $zipPath"

        [System.IO.Compression.ZipFile]::CreateFromDirectory($directoryPath, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false);
        LogSuccess "Zipped:$directoryPath to $zipPath"
    }
    catch {
        LogErrorAndExit "Zip operation failed for:$directoryPath" $_.Exception
    }
}


function LogErrorAndExit($errorMessage, $exception) {
    Write-Output $errorMessage
    if ($exception -ne $null) {
        Write-Output $exception|format-list -force
    }    
    Exit 1
}

function LogSuccess($message) {
    Write-Output `n
    Write-Output $message
}

try 
{
    $artifactsPath = Resolve-Path "..\artifacts\"
    $tempDirectoryPath = "..\artifacts\temp\"

    if (Test-Path $tempDirectoryPath)
    {
        $removed = Remove-Item $tempDirectoryPath -Force -Recurse
        LogSuccess "Removed $tempDirectoryPath"
    }

    # Runtimes with signed binaries
    $runtimesIdentifiers = @("min.win-x86","min.win-x64")
    $tempDirectory = New-Item $tempDirectoryPath -ItemType Directory
    LogSuccess "$tempDirectoryPath created"

    # Unzip the coretools artifact to add signed binaries
    foreach($rid in $runtimesIdentifiers)
    {
        $files= Get-ChildItem -Recurse -Path "..\artifacts\*.zip"
        foreach($file in $files)
        {
            if ($file.Name.Contains($rid))
            {
                $fileName = [io.path]::GetFileNameWithoutExtension($file.Name)

                $targetDirectory = Join-Path $tempDirectoryPath $fileName
                $dir = New-Item $targetDirectory -ItemType Directory
                LogSuccess "created $targetDirectory"

                $targetDirectory = Resolve-Path $targetDirectory 
                $filePath = Resolve-Path $file.FullName
                Unzip $filePath $targetDirectory       
                   
                # Removing file after extraction
                Remove-Item $filePath
                LogSuccess "Removed $filePath"
            }
        }
    }

    # Store file count before replacing the binaries
    $fileCountBefore = (Get-ChildItem $tempDirectoryPath -Recurse | Measure-Object).Count
    LogSuccess "file count $fileCountBefore"

    # copy authenticode signed binaries into extracted directories
    $authenticodeDirectory = "..\artifacts\ToSign\Authenticode\"
    $authenticodeDirectories = Get-ChildItem $authenticodeDirectory -Directory

    foreach($directory in $authenticodeDirectories)
    {
        $sourcePath = $directory.FullName
        $copyti = Copy-Item -Path $sourcePath -Destination $tempDirectoryPath -Recurse -Force
        LogSuccess "Copying $sourcePath to $tempDirectoryPath"
    }

    # copy thirdparty signed directory into extracted directories
    $thirdPathDirectory  = "..\artifacts\ToSign\ThirdParty\"
    $thirdPathDirectories  = Get-ChildItem $thirdPathDirectory -Directory

    foreach($directory in $thirdPathDirectories)
    {
        $sourcePath = $directory.FullName
        Copy-Item -Path $sourcePath -Destination $tempDirectoryPath -Recurse -Force
        LogSuccess "Copying $sourcePath to $tempDirectoryPath"
    }

    $fileCountAfter = (Get-ChildItem $tempDirectoryPath -Recurse | Measure-Object).Count
    LogSuccess "File count after $fileCountAfter"

    if ($fileCountBefore -ne $fileCountAfter)
    {
        LogErrorAndExit "File count does not match. File count before copy: $fileCountBefore != file count after copy:$fileCountAfter" $_.Exception
    }

    $tempDirectories  = Get-ChildItem $tempDirectoryPath -Directory
    foreach($directory in $tempDirectories)
    {
       $directoryName = $directory.Name
       $zipPath = Join-Path $artifactsPath $directoryName
       $zipPath = $zipPath + ".zip"
       $directoryPath = $directory.FullName
       Zip $directoryPath $zipPath 
    }


    $zipFiles  = Get-ChildItem "$artifactsPath\*.zip" -File 
    foreach($zipFile in $zipFiles)
    {
    
        GenerateSha $zipFile.FullName $artifactsPath $zipFile.Name
        LogSuccess 
    }
}
catch {
    LogErrorAndExit "Execution Failed" $_.Exception
}