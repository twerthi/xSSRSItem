#region Helper methods

#region Item-Exists()
Function Find-Item
{
    # Declare parameters
    Param(
    $ItemFolderPath,
    $ItemName,
    $ReportServerProxyNamespace)
    
    # declare search condition
    $SearchCondition = New-Object "$ReportServerProxyNamespace.SearchCondition";

    # fill in properties
    $SearchCondition.Condition = Get-SpecificEnumValue -EnumNamespace "$ReportServerProxyNamespace.ConditionEnum" -EnumName "Equals"
    $SearchCondition.ConditionSpecified = $true
    $SearchCondition.Name = "Name"

	$SearchCondition.Values = @($ItemName)
	# search
	$items = $ReportServerProxy.FindItems($ItemFolderPath, (Get-SpecificEnumValue -EnumNamespace "$ReportServerProxyNamespace.BooleanOperatorEnum" -EnumName "And"), $null, $SearchCondition)

    # check to see if anything was returned
    if($items.Length -gt 0)
    {
        # loop through returned items
        foreach($item in $items)
        {
            # check the path
            if($item.Path -eq "$ItemFolderPath/$ItemName")
            {
                # return true
                return $true
            }
            else
            {
                # warn
                Write-Warning "Unexpected path for $($item.Name); path is $($item.Path) exepected $ItemFolderPath/$ItemName"
            }
        }

        # items were found, but the path doesn't match
        
        return $false
    }
    else
    {
        return $false
    }
}
#endregion

#region Get-SpecificEnumValue()
Function Get-SpecificEnumValue($EnumNamespace, $EnumName)
{
    # get the enum values
    $EnumValues = [Enum]::GetValues($EnumNamespace)

    # Loop through to find the specific value
    foreach($EnumValue in $EnumValues)
    {
        # check current
        if($EnumValue -eq $EnumName)
        {
            # return it
            return $EnumValue
        }
    }

    # nothing was found
    return $null
}
#endregion

#region Normalize-SSRSFolder()
function Format-SSRSFolder ([string]$Folder) {
    if (-not $Folder.StartsWith('/')) {
        $Folder = '/' + $Folder
    }
    
    return $Folder
}
#endregion

#region New-SSRSFolder()
function New-SSRSFolder 
{
    param(
        $Name,
        $ReportServiceProxy
    )
    Write-Verbose "New-SSRSFolder -Name $Name"
 
    $Name = Format-SSRSFolder -Folder $Name -ReportServiceProxy $ReportServiceProxy
 
    if ($ReportServiceProxy.GetItemType($Name) -ne 'Folder') {
        $Parts = $Name -split '/'
        $Leaf = $Parts[-1]
        $Parent = $Parts[0..($Parts.Length-2)] -join '/'
 
        if ($Parent) {
            New-SSRSFolder -Name $Parent -ReportServiceProxy $ReportServiceProxy
        } else {
            $Parent = '/'
        }
        
        $ReportServiceProxy.CreateFolder($Leaf, $Parent, $null)
    }
}
#endregion

#region Get-ObjectNamespace()
Function Get-ObjectNamespace($Object)
{
    # return the value
    ($Object).GetType().ToString().SubString(0, ($Object).GetType().ToString().LastIndexOf("."))
}
#endregion

function New-Policy
{
    param(
        $Users,
        $RoleName,
        $ReportProxyNamespace
    )

    $Policies = @()

    # Loop through defined members
    ForEach ($User in $Users)
    {
        # Create policy object
        $Policy = New-Object "$ReportProxyNamespace.Policy"
        $Policy.GroupUserName = $User

        # Create role object
        $Role = New-Object "$ReportProxyNamespace.Role"
        $Role.Name = $RoleName

        # Add role to policy
        $Policy.Roles += $Role
        $Policies += $Policy
    }

    # return policy
    return $Policies
}

Function Add-Role
{
	Param($UserPolicy,
	$RoleName,
	$ReportProxyNamespace
	)

	# Create role object
	$Role = New-Object "$ReportProxyNamespace.Role"
	$Role.Name = $RoleName

	# Add role to current policy
	$UserPolicy.Roles += $Role

	# Return the updated policy object
	return $UserPolicy
}

Function Remove-Role
{
	# Define parameters
	Param(
		$UserPolicy,
		$RoleName,
		$ReportProxyNamespace
	)

	# Create the role object
	$Role = New-Object "$ReportProxyNamespace.Role"
	$Role.Name = $RoleName

	# Remove the role from the user policy
	$UserPolicy.Roles = ($UserPolicy.Roles | Where-Object {$_.Name -ne $RoleName}) 

	# Return the updated object
	return $UserPolicy
}

Function Set-RolePolicy
{
	# Define parameters
	Param ($Policies,
	$Members,
	$RoleName,
	$ReportServiceProxyNamespace
	)
	
	# Loop through members
	ForEach($Member in $Members)
	{
		# Check to see if the member is in there
		$User = $Policies | Where-Object {$_.GroupUserName -eq $Member}

		# Check to see if User is null
		if($User -eq $null)
		{
			# display work
			Write-Verbose "Creating new policy for $Member, adding $RoleName."

			# This is a new policy
			$Policies += New-Policy -Users $Member -RoleName $RoleName -ReportProxyNamespace $ReportServiceProxyNamespace
		}
		else
		{
			# User is already present, check to see if their roles contains browser
			if(!($User.Roles.Name -contains $RoleName))
			{
				# display work
				Write-Verbose "Adding $RoleName to $Member policy."
			
				# Add this role to the current policy object
				$User = Add-Role -UserPolicy $User -RoleName $RoleName -ReportProxyNamespace $ReportServiceProxyNamespace
			}
		}
	}

	# Get all users who have the role
	$Policy = $Policies | Where-Object {$_.Roles.Name -eq $RoleName}

	# Find all users to remove
#	$UsersToRemove = $Policy | Where-Object {$_.GroupUserName -notcontains $Members}
    $UsersToRemove = @()

    # Loop through the current policy
    ForEach ($UserPolicy in $Policy)
    {
         # Check to see if members has users
         if ($Members -notcontains $UserPolicy.GroupUserName)
         {
            # Add user
            $UsersToRemove += $UserPolicy
         }
    }

	
	# Loop through users to remove from the role
	ForEach ($User in $UsersToRemove)
	{
		# Remove the role
		Remove-Role -UserPolicy $User -RoleName $RoleName -ReportProxyNamespace $ReportServiceProxyNamespace
	}

	# return the policies object
	return $Policies
}

Function Compare-GroupMembership
{
	# Define parameters
	Param ($MembershipPolicy,
	$Members
	)

	# Perform basic test of numbers
	if ($Members.Count -ne $MembershipPolicy.Count)
	{
		# The number of users aren't even
		return $false
	}
	# Just because the number of entries matches, doesn't mean it's right
	else 
	{
		# Loop through returned users
		ForEach ($UserPolicy in $MembershipPolicy)
		{
			# Check browser collection against the policy
			if ($Members -notcontains $UserPolicy.GroupUserName)
			{
				# Return the result
				return $false
			}
		}
	}

	# Everything is just fine
	return $true
}

#endregion

#region DSC Resource methods

#region Get-TargetResource
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]

    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [ValidateNotNullOrEmpty()]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ReportServiceUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ItemPath,

#        [Parameter()]
#        [ValidateNotNullOrEmpty()]
#        $Browser,

#        [Parameter()]
#        [ValidateNotNullOrEmpty()]
#        $ContentManager,

        [Parameter(Mandatory = $true)]
        $Credential
    )

    $Browser = @()
    $ContentManager = @()

    # Create report service proxy
    $ReportServiceProxy = New-WebServiceProxy -Uri $ReportServiceUrl -Credential $Credential

    # Get proxy namespace
    $ReportServiceProxyNamespace = Get-ObjectNamespace -Object $ReportServiceProxy

    # Get the folder we're searching for
    $Item = ($ReportServiceProxy.ListChildren("/", $true) | Where-Object {$_.Path -eq $ItemPath})

    # Declare policies variable
    $Policies = $null

    # Check to see if item exists
    if ($Item -eq $null)
    {
        Write-Verbose -Message "Folder $ItemPath is absent"
        
        # Set ensure to absent
        $Ensure = "Absent"
    }
    else
    {
        Write-Verbose -Message "Folder $ItemPath is present"

        # Set ensure
        $Ensure = "Present"

        # Get current policies
        $InheritParent = $true
        $Policies = $ReportServiceProxy.GetPolicies($Item.Path, [ref]$InheritParent)

        # Loop through all browsers
        $Browsers = $Policies | Where-Object {$_.Roles.Name -eq "Browser"}
        ForEach ($User in $Browsers)
        {
            $Browser += $User.GroupUserName
        }

        # Loop through all content managers
        $ContentManagers = $Policies | Where-Object {$_.Roles.Name -eq "Content Manager"}
        ForEach($User in $ContentManagers)
        {
            $ContentManager += $User.GroupUserName
        }
    }

    $returnValue = @{
        ItemPath = $ItemPath
        Ensure = $Ensure
        Browser = $Browser
        ContentManager = $ContentManager
    }


    $returnValue
}
#endregion

#region Set-TargetResource
function Set-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]

    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [ValidateNotNullOrEmpty()]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ReportServiceUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ItemPath,

        [Parameter()]
        $Browser,

        [Parameter()]
        $ContentManager,

		[Parameter()]
		$MyReports,

		[Parameter()]
		$Publisher,

		[Parameter()]
		$ReportBuilder,

        [Parameter(Mandatory = $true)]
        $Credential,

        [Parameter()]
        $ItemType
    )

    # Create report service proxy
    $ReportServiceProxy = New-WebServiceProxy -Uri $ReportServiceUrl -Credential $Credential

    # Get proxy namespace
    $ReportServiceProxyNamespace = Get-ObjectNamespace -Object $ReportServiceProxy

    # Get the folder we're searching for
    $Item = ($ReportServiceProxy.ListChildren("/", $true) | Where-Object {$_.Path -eq $ItemPath})

    # Check to see if item is there
    if(($Item -eq $null) -and ($ItemType -eq "Folder"))
    {
        # Create the item
        New-SSRSFolder -Name $ItemPath -ReportServiceProxy $ReportServiceProxy

        # Get the folder we're searching for
        $Item = ($ReportServiceProxy.ListChildren("/", $true) | Where-Object {$_.Path -eq $ItemPath})
    }
	
    # Check to see if item exists
    if ($Item -ne $null)
    {
        $InheritParent = $true
        
        # Get existing policies
        $Policies = $ReportServiceProxy.GetPolicies($ItemPath, [ref]$InheritParent)

    #    $Policies = @()

        # Set permissions
        if($Browser -ne $null)
	    {
		    # Check the policy
		    $Policies = Set-RolePolicy -Policies $Policies -Members $Browser -RoleName "Browser" -ReportServiceProxyNamespace $ReportServiceProxyNamespace
	    }

	    if($ContentManager -ne $null)
	    {
		    # Check the policy
		    $Policies = Set-RolePolicy -Policies $Policies -Members $ContentManager -RoleName "Content Manager" -ReportServiceProxyNamespace $ReportServiceProxyNamespace
	    }

	    if($MyReports -ne $null)
	    {
		    # Check the Policy
		    $Policies = Set-RolePolicy -Policies  $Policies -Members $MyReports -RoleName "My Reports" -ReportServiceProxyNamespace $ReportServiceProxyNamespace
	    }

	    if($Publisher -ne $null)
	    {
		    # Check the policy
		    $Policies = Set-RolePolicy -Policies $Policies -Members $Publisher -RoleName "Publisher" -ReportServiceProxyNamespace $ReportServiceProxyNamespace	
	    }

	    if($ReportBuilder -ne $null)
	    {
		    # Check the policy
		    $Policies = Set-RolePolicy -Policies $Policies -Members $ReportBuilder -RoleName "Report Builder" -ReportServiceProxyNamespace $ReportServiceProxyNamespace	
	    }
	
	    # Find the users that no longer have roles and remove them
	    $Policies = ($Policies | Where-Object {$_.Roles -ne $null})

	    # update
        $ReportServiceProxy.SetPolicies($ItemPath, $Policies)
    }
    else
    {
        # Display warning that item doesn't exist
        Write-Warning "Unable to set security, $ItemPath does not exist."
    }
}
#endregion

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]

    param
    (
        [Parameter()]
        [ValidateSet('Present', 'Absent')]
        [ValidateNotNullOrEmpty()]
        $Ensure = 'Present',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ReportServiceUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ItemPath,

        [Parameter()]
        $Browser,

        [Parameter()]
        $ContentManager,

		[Parameter()]
		$MyReports,

		[Parameter()]
		$Publisher,

		[Parameter()]
		$ReportBuilder,

        [Parameter(Mandatory = $true)]
        $Credential,

        [Parameter()]
        $ItemType
    )

    $InDesiredState = $true

    # Create report service proxy
    $ReportServiceProxy = New-WebServiceProxy -Uri $ReportServiceUrl -Credential $Credential

    # Get proxy namespace
    $ReportServiceProxyNamespace = Get-ObjectNamespace -Object $ReportServiceProxy

    # Get the folder we're searching for
    $Item = ($ReportServiceProxy.ListChildren("/", $true) | Where-Object {$_.Path -eq $ItemPath})

    # Check to see if it exists
    if (($Item -eq $null) -and ($Ensure -eq "Present"))
    {
        # Display not in desired stat
        Write-Verbose "Reporting Services item $ItemPath does not exist."
        
        # Mark not in desired state
        #$InDesiredState = $false
		return $false
    }
    else
    {
        $InheritParent = $true
		$MissingUsers = @()
        
        # Get existing policies
        $Policies = $ReportServiceProxy.GetPolicies($ItemPath, [ref]$InheritParent)

        # Get policies
        $BrowserPolicy = $Policies | Where-Object {$_.Roles.Name -eq "Browser"}
        $ContentManagerPolicy = $Policies | Where-Object {$_.Roles.Name -eq "Content Manager"}
		$MyReportsPolicy = $Policies | Where-Object {$_.Roles.Name -eq "My Reports"}
		$PublisherPolicy = $Policies | Where-Object {$_.Roles.Name -eq "Publisher"}
		$ReportBuilderPolicy = $Policies | Where-Object {$_.Roles.Name -eq "Report Builder"}

		# Check the Browsers collection
		Write-Verbose "Checking Browser role membership."

		if (!(Compare-GroupMembership -MembershipPolicy $BrowserPolicy -Members $Browser))
		{
			# Display results
			Write-Verbose "Browser membership not in desired state."
		
			# The number of users aren't even
			return $false			
		}

		Write-Verbose "Checking Content Manager role membership."

		if (!(Compare-GroupMembership -MembershipPolicy $ContentManagerPolicy -Members $ContentManager))
		{
			Write-Verbose "Content Manager membership not in desired state."

			return $false
		}

		Write-Verbose "Checking My Reports role membership."

		if (!(Compare-GroupMembership -MembershipPolicy $MyReportsPolicy -Members $MyReports))
		{
			Write-Verbose "My Reports membership not in desired state."

			return $false
		}

		Write-Verbose "Checking Publisher role membership."

		if (!(Compare-GroupMembership -MembershipPolicy $PublisherPolicy -Members $Publisher))
		{
			Write-Verbose "Publisher membership not in desired state"

			return $false
		}

		Write-Verbose "Checking Report Builder role membership"

		if (!(Compare-GroupMembership -MembershipPolicy $ReportBuilderPolicy -Members $ReportBuilder))
		{
			Write-Verbose "Report Builder role not in desired state."

			return $false
		}

        # Display everything is in order
        Write-Verbose "$ItemPath is in desired state, no action required."
    }

    return $InDesiredState
}

#endregion