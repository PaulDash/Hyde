function convertToHydeHashtable {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        # Normalize YAML and PSCustomObject output into plain hashtables/arrays for predictable downstream use.
        if ($InputObject -is [System.Collections.IDictionary]) {
            $result = @{}
            foreach ($key in $InputObject.Keys) {
                $result[$key] = convertToHydeHashtable -InputObject $InputObject[$key]
            }

            return $result
        }

        if ($InputObject -is [pscustomobject]) {
            $result = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $result[$property.Name] = convertToHydeHashtable -InputObject $property.Value
            }

            return $result
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $result = New-Object System.Collections.ArrayList
            foreach ($item in $InputObject) {
                [void]$result.Add((convertToHydeHashtable -InputObject $item))
            }

            return ,$result.ToArray()
        }

        return $InputObject
    }
}

function copyHydeValue {
    [CmdletBinding()]
    param(
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    # Build context copies should be detached from the original settings tree before runtime values are added.
    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = @{}
        foreach ($key in $InputObject.Keys) {
            $copy[$key] = copyHydeValue -InputObject $InputObject[$key]
        }

        return $copy
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $copy = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$copy.Add((copyHydeValue -InputObject $item))
        }

        return ,$copy.ToArray()
    }

    return $InputObject
}

function getHydeMarkdownExtensions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    $extensions = @('.md', '.markdown')

    # Jekyll-style markdown_ext values are stored as a comma-separated string in configuration.
    if ($Settings.ContainsKey('markdown_ext') -and $Settings.markdown_ext) {
        $extensions = @(
            $Settings.markdown_ext -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ } |
                ForEach-Object {
                    if ($_.StartsWith('.')) {
                        $_.ToLowerInvariant()
                    } else {
                        ".$($_.ToLowerInvariant())"
                    }
                }
        )
    }

    return $extensions
}
